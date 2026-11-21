import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'db.dart';
import 'store.dart';
import 'sync.dart';
import 'util.dart';

class BackupError implements Exception {
  final String message;
  BackupError(this.message);
  @override
  String toString() => message;
}

class ImportPlan {
  final List<Map<String, dynamic>> toAdd, differ;
  final int same;
  final String createdAt;
  final Map<String, dynamic> payload;
  ImportPlan(this.toAdd, this.differ, this.same, this.createdAt, this.payload);
}

/// Encrypted, password-protected, text-only backups of the whole organization (records and their relationships).
/// File layout (JSON): header + AES-256-CBC encrypted payload + SHA-256 of the payload for the integrity check.
class Backup {
  static const _iterations = 20000;
  static const _format = 'freely-backup';

  // ------------------------------------------------------------------ key derivation (PBKDF2-HMAC-SHA256)
  static Uint8List _key(String password, Uint8List salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
    final t = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(hmac.convert(u).bytes);
      for (var j = 0; j < t.length; j++) {
        t[j] ^= u[j];
      }
    }
    return t;
  }

  static Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(base.path, 'backups'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  // ------------------------------------------------------------------ create
  /// Text only: no logo or images. Soft-deleted markers are kept so that a restore keeps deletions consistent.
  static Future<String> _payload() async {
    final app = AppState.instance;
    final recs = await Db.instance.all(app.orgId);
    return jsonEncode({
      'format': _format, 'formatVersion': 2, 'createdAt': nowIso(), 'app': 'Freely NGO',
      'orgId': app.orgId, 'orgName': app.orgName, 'orgCode': app.orgCode,
      'counts': {for (final t in [tBeneficiary, tPerson, tAttendance, tDonation, tExpense, tItem]) t: recs.where((r) => r.type == t && !r.deleted).length},
      'entities': [for (final r in recs) r.toWire()],
    });
  }

  static String encrypt(String plain, String password) {
    final salt = Uint8List.fromList(enc.SecureRandom(16).bytes);
    final iv = enc.IV.fromSecureRandom(16);
    final key = enc.Key(_key(password, salt, _iterations));
    final cipher = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc)).encryptBytes(utf8.encode(plain), iv: iv);
    return jsonEncode({
      'fcms': 1, 'kdf': 'pbkdf2-sha256', 'iter': _iterations,
      'salt': base64Encode(salt), 'iv': iv.base64, 'sha256': sha256.convert(utf8.encode(plain)).toString(),
      'data': cipher.base64,
    });
  }

  /// Returns the readable payload, or throws [BackupError] (not a backup / wrong password / damaged).
  static Map<String, dynamic> decrypt(String fileText, String password) {
    final Map<String, dynamic> h;
    try {
      h = jsonDecode(fileText) as Map<String, dynamic>;
      if (h['fcms'] != 1 || h['data'] is! String) throw const FormatException();
    } catch (_) {
      throw BackupError('This is not an Freely NGO backup file.');
    }
    final String plain;
    try {
      final key = enc.Key(_key(password, base64Decode(h['salt'] as String), (h['iter'] as int?) ?? _iterations));
      final bytes = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc))
          .decryptBytes(enc.Encrypted.fromBase64(h['data'] as String), iv: enc.IV.fromBase64(h['iv'] as String));
      plain = utf8.decode(bytes);
    } catch (_) {
      throw BackupError('Wrong password, or the backup file is damaged.');
    }
    if (sha256.convert(utf8.encode(plain)).toString() != h['sha256']) {
      throw BackupError('Integrity check failed: the backup file is damaged or was changed.');
    }
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      throw BackupError('The backup content could not be read.');
    }
    if (payload['format'] != _format || payload['entities'] is! List) throw BackupError('This is not an Freely NGO backup file.');
    return payload;
  }

  /// Creates a backup file in the app's private folder and records it in the backup history.
  static Future<File> create(String password, {String kind = 'manual'}) async {
    final text = encrypt(await _payload(), password);
    final d = await _dir();
    final org = AppState.instance.orgName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
    final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(RegExp(r'[-:]'), '').replaceAll('T', '_');
    final f = File(p.join(d.path, 'Freely NGO_${org}_$stamp.fngobak'));
    await f.writeAsString(text, flush: true);
    await Db.instance.addBackup(kind, await f.length(), 'ok', path: f.path);
    return f;
  }

  // ------------------------------------------------------------------ check / restore
  static bool _validEntity(dynamic raw) =>
      raw is Map && raw['id'] is String && raw['data'] is Map && entityTypes.contains(raw['type']) && raw['hash'] is String && raw['version'] is int;

  /// Integrity + organization check without changing anything.
  static Future<ImportPlan> inspect(String fileText, String password) async {
    final payload = decrypt(fileText, password);
    final app = AppState.instance;
    if (payload['orgId'] != app.orgId) {
      throw BackupError('This backup belongs to a different organization and cannot be restored here.');
    }
    final toAdd = <Map<String, dynamic>>[], differ = <Map<String, dynamic>>[];
    var same = 0;
    for (final raw in payload['entities'] as List) {
      if (!_validEntity(raw)) throw BackupError('The backup contains invalid records, so nothing was restored.');
      final e = Map<String, dynamic>.from(raw as Map);
      final local = await Db.instance.get(e['id'] as String);
      if (local == null) {
        toAdd.add(e);
      } else if (local.hash == e['hash']) {
        same++;
      } else {
        differ.add(e);
      }
    }
    return ImportPlan(toAdd, differ, same, (payload['createdAt'] ?? '') as String, payload);
  }

  static Rec _fromWire(Map<String, dynamic> e, {bool dirty = true}) => Rec(
        id: e['id'] as String, orgId: AppState.instance.orgId, type: e['type'] as String,
        data: Map<String, dynamic>.from(e['data'] as Map), version: e['version'] as int,
        updatedAt: (e['updatedAt'] as String?) ?? nowIso(), by: (e['by'] as String?) ?? '', deleted: e['deleted'] == true,
        hash: e['hash'] as String, lineage: List<String>.from((e['lineage'] as List?) ?? const []), dirty: dirty);

  /// Applies a checked backup. Existing records are only replaced when [overwrite] is true (the user confirmed);
  /// a replaced record is stored as a new edit, so the other devices accept it instead of treating it as a conflict.
  static Future<int> apply(ImportPlan plan, {required bool overwrite}) async {
    final db = Db.instance;
    final changed = <Rec>[];
    var n = 0;
    for (final e in plan.toAdd) {
      final r = _fromWire(e)..dirty = !AppState.instance.isLocal;
      await db.put(r, notify: false);
      changed.add(r);
      n++;
    }
    if (overwrite) {
      for (final e in plan.differ) {
        final l = await db.get(e['id'] as String);
        if (l == null) continue;
        l.edit(by: AppState.instance.mobile, newData: Map<String, dynamic>.from(e['data'] as Map), isDeleted: e['deleted'] == true, minVersion: e['version'] as int);
        l.dirty = !AppState.instance.isLocal;
        await db.put(l, notify: false);
        changed.add(l);
        n++;
      }
    }
    await Store.audit('restored', 'backup', '', '$n records restored from backup');
    await db.addBackup('restore', 0, 'ok', note: '$n records');
    db.bump();
    SyncEngine.instance.trigger();
    return n;
  }

  // ------------------------------------------------------------------ scheduled backup
  /// Once a day, when "Automatic backup" is on and a backup password has been set. Keeps the 7 newest automatic files.
  static Future<void> runAutoIfDue() async {
    final app = AppState.instance;
    try {
      if (!app.autoBackup || !app.approved) return;
      final pw = await Db.instance.getKv('auto_backup_pw');
      if (pw == null || pw.isEmpty) return;
      final last = parseDate(await Db.instance.getKv('last_auto_backup'));
      if (last != null && DateTime.now().toUtc().difference(last).inHours < 24) return;
      await create(pw, kind: 'automatic');
      await Db.instance.setKv('last_auto_backup', nowIso());
      final autos = (await Db.instance.backups()).where((b) => b['kind'] == 'automatic' && b['path'] != null).toList();
      for (final old in autos.skip(7)) {
        final f = File(old['path'] as String);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {
      await Db.instance.addBackup('automatic', 0, 'failed');
    }
  }

  static Future<bool> fileExists(String? path) async => path != null && await File(path).exists();
}
