import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common/utils/utils.dart' show firstIntValue;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

String _newHash(String id, int version, Object data, bool deleted, String by, String at) {
  final salt = Random.secure().nextInt(1 << 32);
  return sha1.convert(utf8.encode('$id|$version|${jsonEncode(data)}|$deleted|$by|$at|$salt')).toString().substring(0, 16);
}

/// One synchronised record (member, attendance, event, announcement, transaction, audit entry, ...).
/// Sync between devices is based on: unique id, version number, timestamp, soft-delete marker and a `lineage`
/// (the hashes of the earlier states of the record). Lineage lets a device tell "the other copy is newer" from
/// "both of us changed it" (a conflict).
class Rec {
  final String id, orgId, type;
  Map<String, dynamic> data;
  int version;
  String updatedAt;
  String by;                 // e-mail of whoever made the last change
  bool deleted;
  bool dirty;                // changed here and not yet delivered to another device
  String hash;               // identifies this exact state
  List<String> lineage;      // hashes of the states this one was made from
  Map<String, dynamic>? conflict;   // the other device's copy, kept until the user decides

  Rec({required this.id, required this.orgId, required this.type, required this.data, this.version = 1,
      required this.updatedAt, this.by = '', this.deleted = false, this.dirty = false, String? hash,
      List<String>? lineage, this.conflict})
      : hash = hash ?? _newHash(id, version, data, deleted, by, updatedAt),
        lineage = lineage ?? [];

  factory Rec.fromRow(Map<String, Object?> r) => Rec(
        id: r['id'] as String,
        orgId: r['org_id'] as String,
        type: r['type'] as String,
        data: Map<String, dynamic>.from(jsonDecode(r['data'] as String) as Map),
        version: r['version'] as int,
        updatedAt: r['updated_at'] as String,
        by: (r['by_user'] as String?) ?? '',
        deleted: (r['deleted'] as int) == 1,
        dirty: (r['dirty'] as int) == 1,
        hash: r['hash'] as String,
        lineage: List<String>.from(jsonDecode((r['lineage'] as String?) ?? '[]') as List),
        conflict: r['conflict'] == null ? null : Map<String, dynamic>.from(jsonDecode(r['conflict'] as String) as Map),
      );

  Map<String, Object?> toRow() => {
        'id': id, 'org_id': orgId, 'type': type, 'data': jsonEncode(data), 'version': version, 'updated_at': updatedAt,
        'by_user': by, 'deleted': deleted ? 1 : 0, 'dirty': dirty ? 1 : 0, 'hash': hash, 'lineage': jsonEncode(lineage),
        'conflict': conflict == null ? null : jsonEncode(conflict),
      };

  /// What travels between devices.
  Map<String, dynamic> toWire() => {
        'id': id, 'type': type, 'data': data, 'version': version, 'updatedAt': updatedAt, 'by': by,
        'deleted': deleted, 'hash': hash, 'lineage': lineage,
      };

  /// Records a new edit made on this device.
  void edit({required String by, Map<String, dynamic>? newData, bool? isDeleted, List<String> alsoDescendsFrom = const [], int minVersion = 0}) {
    lineage = {...lineage, hash, ...alsoDescendsFrom}.toList();
    if (lineage.length > 64) lineage = lineage.sublist(lineage.length - 64);
    version = max(version, minVersion) + 1;
    if (newData != null) data = newData;
    if (isDeleted != null) deleted = isDeleted;
    this.by = by;
    updatedAt = DateTime.now().toUtc().toIso8601String();
    hash = _newHash(id, version, data, deleted, by, updatedAt);
    dirty = true;
  }

  String s(String k) => (data[k] ?? '').toString();
  int i(String k) => data[k] is int ? data[k] as int : int.tryParse('${data[k]}') ?? 0;
}

/// The phone's SQLite database. Everything is written here first; the sync engine shares it with the other devices.
class Db {
  Db._();
  static final Db instance = Db._();
  Database? _d;

  /// Tests point the database at a temporary file.
  static String? testPath;

  /// Bumped after every change so that screens can reload.
  final ValueNotifier<int> changes = ValueNotifier(0);
  void bump() => changes.value++;

  Future<Database> get db async => _d ??= await _open();

  Future<Database> _open() async {
    sqfliteFfiInit();
    final String path;
    if (testPath != null) {
      path = testPath!;
    } else {
      final dir = await getApplicationSupportDirectory();
      await Directory(dir.path).create(recursive: true);
      path = p.join(dir.path, 'freelyngo.db');
    }
    return databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: (d, v) async {
      await d.execute('CREATE TABLE kv(k TEXT PRIMARY KEY, v TEXT)');
      await d.execute('''CREATE TABLE entities(
        id TEXT PRIMARY KEY, org_id TEXT NOT NULL, type TEXT NOT NULL, data TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 1, updated_at TEXT NOT NULL, by_user TEXT,
        deleted INTEGER NOT NULL DEFAULT 0, dirty INTEGER NOT NULL DEFAULT 0,
        hash TEXT NOT NULL, lineage TEXT, conflict TEXT)''');
      await d.execute('CREATE INDEX entities_org_type ON entities(org_id, type)');
      await d.execute('''CREATE TABLE backups(
        id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, kind TEXT NOT NULL,
        size INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL, path TEXT, note TEXT)''');
    }));
  }

  // ------------------------------------------------------------------ key/value (settings, session, keys, sync state)
  Future<String?> getKv(String k) async {
    final r = await (await db).query('kv', where: 'k=?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }

  Future<void> setKv(String k, String? v) async {
    final d = await db;
    if (v == null) {
      await d.delete('kv', where: 'k=?', whereArgs: [k]);
    } else {
      await d.insert('kv', {'k': k, 'v': v}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // ------------------------------------------------------------------ records
  Future<List<Rec>> list(String orgId, String type, {bool includeDeleted = false}) async {
    final r = await (await db).query('entities',
        where: includeDeleted ? 'org_id=? AND type=?' : 'org_id=? AND type=? AND deleted=0', whereArgs: [orgId, type]);
    return r.map(Rec.fromRow).toList();
  }

  Future<List<Rec>> all(String orgId) async =>
      (await (await db).query('entities', where: 'org_id=?', whereArgs: [orgId])).map(Rec.fromRow).toList();

  Future<Rec?> get(String id) async {
    final r = await (await db).query('entities', where: 'id=?', whereArgs: [id]);
    return r.isEmpty ? null : Rec.fromRow(r.first);
  }

  Future<void> put(Rec r, {bool notify = true}) async {
    await (await db).insert('entities', r.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);
    if (notify) bump();
  }

  Future<int> dirtyCount(String orgId) async =>
      firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM entities WHERE org_id=? AND dirty=1', [orgId])) ?? 0;

  Future<void> clearDirty(String orgId) async {
    await (await db).update('entities', {'dirty': 0}, where: 'org_id=? AND dirty=1', whereArgs: [orgId]);
    bump();
  }

  Future<List<Rec>> conflicts(String orgId) async =>
      (await (await db).query('entities', where: 'org_id=? AND conflict IS NOT NULL', whereArgs: [orgId])).map(Rec.fromRow).toList();

  Future<void> wipeOrg(String orgId) async {
    await (await db).delete('entities', where: 'org_id=?', whereArgs: [orgId]);
    bump();
  }

  // ------------------------------------------------------------------ backup history
  Future<int> addBackup(String kind, int size, String status, {String? path, String? note}) async =>
      (await db).insert('backups', {'created_at': DateTime.now().toUtc().toIso8601String(), 'kind': kind, 'size': size, 'status': status, 'path': path, 'note': note});

  Future<List<Map<String, Object?>>> backups() async => (await db).query('backups', orderBy: 'id DESC', limit: 100);
}
