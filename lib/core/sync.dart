import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'cloud.dart';
import 'db.dart';
import 'store.dart';
import 'users.dart';
import 'util.dart';

/// Keeps the phone's SQLite database and the organization's Google Sheet in step.
///
///  * every change is saved on the phone first (dirty = not yet in the sheet)
///  * when the internet is on, the dirty records are sent to the sheet (through the Apps Script web app) and everything that other
///    phones changed is downloaded, so the sheet and all phones end up the same
///  * nothing is silently overwritten: every change remembers the states it came from (its "lineage"). A copy that descends from
///    the other one replaces it; an older copy is ignored; if both phones changed the same record it is a CONFLICT and the user
///    chooses which version to keep
///  * failed syncs are retried automatically (when the connection returns, after every change, and every 2 hours)
class SyncEngine {
  SyncEngine._();
  static final SyncEngine instance = SyncEngine._();

  final ValueNotifier<int> pending = ValueNotifier(0);
  final ValueNotifier<int> conflictCount = ValueNotifier(0);
  final ValueNotifier<bool> running = ValueNotifier(false);
  final ValueNotifier<bool> connected = ValueNotifier(false);   // the last attempt reached the spreadsheet
  final ValueNotifier<int> tick = ValueNotifier(0);             // lastSync / lastError changed
  String? lastSync, lastError;

  Timer? _periodic, _poll, _debounce;
  StreamSubscription? _conn;

  AppState get _app => AppState.instance;

  // ------------------------------------------------------------------ lifecycle
  Future<void> init() async {
    lastSync = await Db.instance.getKv('last_sync');
    Db.instance.changes.addListener(refreshCounts);
    await refreshCounts();
    _conn = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) trigger();
    });
    await start();
  }

  /// (Re)starts the timers for the current login state. Safe to call again after login / approval / logout.
  Future<void> start() async {
    await stop();
    if (_app.session == null || _app.isLocal || _app.sheetUrl.isEmpty) return;
    final status = _app.session?['status'];
    if (status == 'approved') {
      _periodic = Timer.periodic(const Duration(hours: 2), (_) => syncNow(withUsers: true));
      Users.loadCount();
      syncNow(withUsers: true);
    } else if (status == 'pending') {
      _poll = Timer.periodic(const Duration(seconds: 12), (_) => pollApproval());
      pollApproval();
    }
  }

  Future<void> stop() async {
    _periodic?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
  }

  Future<void> refreshCounts() async {
    final id = _app.orgId;
    if (id.isEmpty) {
      pending.value = 0;
      conflictCount.value = 0;
      return;
    }
    pending.value = await Db.instance.dirtyCount(id);
    conflictCount.value = (await Db.instance.conflicts(id)).length;
  }

  /// Sync soon (called after every local change; waits 3 seconds so a burst of edits is uploaded together).
  void trigger() {
    if (_app.isLocal || !_app.approved) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 3), () => syncNow());
  }

  Future<bool> _online() async => (await Connectivity().checkConnectivity()).any((x) => x != ConnectivityResult.none);

  // ------------------------------------------------------------------ waiting for approval (new user phone)
  Future<void> pollApproval() async {
    try {
      final r = await Sheets.call(_app.sheetUrl, {'action': 'status', 'orgCode': _app.orgCode, 'mobile': _app.mobile, 'deviceId': _app.deviceId});
      final st = r['status'];
      if (st == 'approved' && r['token'] != null) {
        await _app.approvedAs(role: 'user', apiToken: r['token'] as String);
        await start();
      } else if (st == 'rejected' || st == 'disabled') {
        await _app.setStatus('disabled');
        await stop();
      }
    } catch (_) {/* offline or the admin has not answered yet: try again in a few seconds */}
  }

  // ------------------------------------------------------------------ the sync itself
  /// Returns a short message for the "Sync Now" button. With [manual] errors are thrown so they can be shown.
  Future<String> syncNow({bool manual = false, bool withUsers = false}) async {
    if (_app.isLocal || _app.session == null) return 'Local mode: everything stays on this phone.';
    if (!_app.approved) return 'Waiting for approval.';
    if (running.value) return 'A sync is already running.';
    if (!await _online()) {
      connected.value = false;
      lastError = 'No internet connection';
      tick.value++;
      if (manual) throw Exception('No internet connection');
      return lastError!;
    }
    running.value = true;
    var sent = 0, received = 0;
    try {
      var since = int.tryParse(await Db.instance.getKv('last_rev') ?? '0') ?? 0;
      while (true) {
        final all = await Db.instance.all(_app.orgId);
        final dirty = all.where((r) => r.dirty && r.conflict == null).toList()..sort((a, b) => _rank(a.type).compareTo(_rank(b.type)));
        final batch = dirty.take(100).toList();
        final resp = await Sheets.authed('sync', {'since': since, 'changes': [for (final r in batch) r.toWire()]});
        await _applyRoles(resp);
        final acc = await _handle(resp);
        sent += acc;
        received += ((resp['records'] as List?) ?? const []).length;
        final reset = _rolesChanged;
        since = reset ? 0 : (resp['rev'] as num).toInt();
        _rolesChanged = false;
        await Db.instance.setKv('last_rev', '$since');
        if (reset) continue;     // roles changed: fetch everything the new roles may see
        final more = resp['more'] == true;
        final remaining = dirty.length > batch.length && acc > 0;
        if (!more && !remaining) break;
      }
      lastSync = nowIso();
      lastError = null;
      connected.value = true;
      await Db.instance.setKv('last_sync', lastSync);
      Db.instance.bump();
      if (withUsers && _app.isAdmin) {
        try {
          await Users.refresh();
        } catch (_) {}
      }
      return 'Synced: $sent sent, $received received.';
    } on SheetsError catch (e) {
      lastError = e.message;
      connected.value = e.code == 'DENIED';
      if (e.code == 'DENIED') await _denied(e);
      if (manual) rethrow;
      return e.message;
    } catch (e) {
      lastError = Sheets.explain(e);
      connected.value = false;
      if (manual) rethrow;
      return lastError!;
    } finally {
      running.value = false;
      tick.value++;
      await refreshCounts();
    }
  }

  /// The admin may change this person's roles; new roles can make more records visible, so everything is fetched again.
  Future<void> _applyRoles(Map<String, dynamic> resp) async {
    final r = resp['roles'];
    if (r is! List) return;
    final now = [for (final x in r) x.toString()];
    final branch = (resp['branch'] ?? '').toString();
    if (now.join(',') == _app.roles.join(',') && branch == _app.branch) return;
    await _app.setRoles(now);
    await _app.setBranch(branch);
    await Db.instance.setKv('last_rev', '0');
    _rolesChanged = true;
  }

  bool _rolesChanged = false;

  int _rank(String t) => (t == tBranch || t == tBeneficiary) ? 0 : 1;   // branches and beneficiaries before records that refer to them

  /// Applies the sheet's answer. Returns how many of this phone's changes the sheet accepted.
  Future<int> _handle(Map<String, dynamic> resp) async {
    final db = Db.instance;
    var n = 0;
    for (final a in (resp['accepted'] as List? ?? const [])) {
      final l = await db.get((a as Map)['id'] as String);
      n++;
      if (l != null && l.hash == a['hash'] && l.dirty) {
        l.dirty = false;
        await db.put(l, notify: false);
      }
    }
    for (final c in (resp['conflicts'] as List? ?? const [])) {
      final server = Map<String, dynamic>.from((c as Map)['server'] as Map);
      final l = await db.get(c['id'] as String);
      if (l != null && l.hash != server['hash'] && l.conflict?['hash'] != server['hash']) {
        l.conflict = server;
        await db.put(l, notify: false);
      }
    }
    for (final raw in (resp['records'] as List? ?? const [])) {
      await _apply(Map<String, dynamic>.from(raw as Map));
    }
    return n;
  }

  /// Applies one record received from the sheet.
  Future<void> _apply(Map<String, dynamic> w) async {
    final type = w['type'];
    final id = w['id'];
    if (type is! String || id is! String || !entityTypes.contains(type) || w['data'] is! Map || w['hash'] is! String) return;
    final data = Map<String, dynamic>.from(w['data'] as Map);
    final lineage = List<String>.from((w['lineage'] as List?) ?? const []);
    final inHash = w['hash'] as String;
    final inVersion = (w['version'] as num?)?.toInt() ?? 1;
    final inUpdated = (w['updatedAt'] as String?) ?? nowIso();
    final inDeleted = w['deleted'] == true;

    final local = await Db.instance.get(id);
    Rec changed;
    if (local == null) {
      changed = Rec(id: id, orgId: _app.orgId, type: type, data: data, version: inVersion, updatedAt: inUpdated,
          by: (w['by'] as String?) ?? '', deleted: inDeleted, hash: inHash, lineage: lineage);
    } else if (local.hash == inHash) {
      return;
    } else if (lastWriterWinsTypes.contains(type)) {
      final newer = inVersion > local.version || (inVersion == local.version && inUpdated.compareTo(local.updatedAt) > 0);
      if (!newer) return;
      changed = _overwrite(local, w, data, lineage);
    } else if (lineage.contains(local.hash)) {
      changed = _overwrite(local, w, data, lineage);                  // the sheet's copy was made from mine: take it
      if (local.conflict != null && lineage.contains(local.conflict!['hash'])) changed.conflict = null;
    } else if (local.lineage.contains(inHash)) {
      return;                                                         // the sheet's copy is older than mine: ignore
    } else {
      if (local.conflict?['hash'] == inHash) return;
      local.conflict = {...w};                                        // both changed it: keep both, ask the user
      await Db.instance.put(local, notify: false);
      return;
    }
    await Db.instance.put(changed, notify: false);
    if (type == tSettings) await _app.applySettings(changed.data);
  }

  Rec _overwrite(Rec local, Map<String, dynamic> w, Map<String, dynamic> data, List<String> lineage) {
    local.data = data;
    local.version = (w['version'] as num?)?.toInt() ?? local.version + 1;
    local.updatedAt = (w['updatedAt'] as String?) ?? nowIso();
    local.by = (w['by'] as String?) ?? '';
    local.deleted = w['deleted'] == true;
    local.hash = w['hash'] as String;
    local.lineage = lineage;
    local.dirty = false;
    return local;
  }

  /// The admin disabled this user, logged everybody out, or this phone is no longer approved.
  Future<void> _denied(SheetsError e) async {
    switch (e.status) {
      case 'disabled':
        await stop();
        await Db.instance.wipeOrg(_app.orgId);
        await _app.setStatus('disabled');
      case 'loggedout' || 'rejected' || 'pending':
        await stop();
        await _app.logout();
      default:
        break;   // 'unknown': keep the data, just report it
    }
  }

  // ------------------------------------------------------------------ conflict resolution
  Future<void> resolve(Rec r, {required bool keepMine}) async {
    final c = r.conflict;
    if (c == null) return;
    final theirHash = c['hash'] as String;
    final theirLineage = List<String>.from((c['lineage'] as List?) ?? const []);
    r.conflict = null;
    r.edit(
      by: _app.mobile,
      newData: keepMine ? null : Map<String, dynamic>.from(c['data'] as Map),
      isDeleted: keepMine ? null : c['deleted'] == true,
      alsoDescendsFrom: [theirHash, ...theirLineage],   // the new state descends from BOTH copies, so it wins everywhere
      minVersion: (c['version'] as num?)?.toInt() ?? 0,
    );
    r.dirty = true;
    await Db.instance.put(r);
    await Store.audit(keepMine ? 'conflict: kept my version' : 'conflict: kept other version', r.type, r.id, r.s('name').isEmpty ? r.type : r.s('name'));
    trigger();
  }

  void dispose() {
    _conn?.cancel();
    _periodic?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
  }
}
