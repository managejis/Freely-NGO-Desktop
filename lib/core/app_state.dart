import 'dart:convert';

import 'package:flutter/material.dart';

import 'db.dart';
import 'util.dart';

/// Who is logged in, which organization, and the app's own settings. Persisted in the phone's database,
/// so login is a one-time activity: after the first successful login (and admin approval) the app opens straight in.
class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  bool loaded = false;
  /// mobile (the identity), name, role (admin|user), status (pending|approved|disabled), orgId, local (true = this phone only), loggedInAt
  Map<String, dynamic>? session;
  /// id, name, code, logo (base64), alertDays, lowStock
  Map<String, dynamic>? org;
  String sheetUrl = '';            // the Apps Script web app of the organization's Google Sheet ('' = local mode)
  String token = '';               // this phone's secret (user: issued on approval, admin: the admin key)
  String deviceId = '';
  ThemeMode themeMode = ThemeMode.system;
  bool autoBackup = false;

  bool get isAdmin => session?['role'] == 'admin';
  /// NGO roles (home manager, doctor, accountant, ...). A person can hold several. The admin implicitly holds all.
  List<String> get roles => [for (final r in (session?['roles'] as List? ?? const [])) r.toString()];
  /// The branch this person is assigned to ('' = all branches).
  String get branch => ((session?['branch'] ?? '') as String);
  bool get isLocal => session?['local'] == true;
  bool get approved => session?['status'] == 'approved';
  String get mobile => (session?['mobile'] ?? '') as String;
  String get userName => ((session?['name'] ?? '') as String).isEmpty ? mobile : session!['name'] as String;
  String get orgId => (org?['id'] ?? session?['orgId'] ?? '') as String;
  String get orgName => (org?['name'] ?? 'Freely NGO') as String;
  String get orgCode => (org?['code'] ?? '') as String;
  String? get logo => org?['logo'] as String?;

  Future<void> load() async {
    final db = Db.instance;
    final s = await db.getKv('session');
    if (s != null) session = Map<String, dynamic>.from(jsonDecode(s) as Map);
    final o = await db.getKv('org');
    if (o != null) org = Map<String, dynamic>.from(jsonDecode(o) as Map);
    sheetUrl = await db.getKv('sheet_url') ?? '';
    token = await db.getKv('api_token') ?? '';
    deviceId = await db.getKv('device_id') ?? '';
    if (deviceId.isEmpty) {
      deviceId = newId();
      await db.setKv('device_id', deviceId);
    }
    themeMode = switch (await db.getKv('theme')) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system };
    autoBackup = (await db.getKv('auto_backup')) == '1';
    loaded = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final db = Db.instance;
    await db.setKv('session', session == null ? null : jsonEncode(session));
    await db.setKv('org', org == null ? null : jsonEncode(org));
    await db.setKv('sheet_url', sheetUrl.isEmpty ? null : sheetUrl);
    await db.setKv('api_token', token.isEmpty ? null : token);
    notifyListeners();
  }

  /// The admin created the organization (online: [url] and the admin key [adminToken] come from the sheet; local mode: both empty).
  Future<void> becomeAdmin({required String mobile, required Map<String, dynamic> orgRow, required String adminName, String url = '', String adminToken = ''}) async {
    sheetUrl = url;
    token = adminToken;
    session = {
      'mobile': mobile, 'name': adminName.trim(), 'role': 'admin', 'status': 'approved', 'orgId': orgRow['id'],
      'loggedInAt': nowIso(), if (url.isEmpty) 'local': true,
    };
    org = {'id': orgRow['id'], 'name': orgRow['name'], 'code': orgRow['code'], 'logo': null};
    await _save();
  }

  /// A user entered a valid invite; now waiting for the admin to approve this phone.
  Future<void> requestedJoin(String mobile, Map<String, dynamic> orgRow, String name, String url) async {
    sheetUrl = url;
    token = '';
    session = {'mobile': mobile, 'name': name.trim(), 'role': 'user', 'status': 'pending', 'orgId': orgRow['id']};
    org = {'id': orgRow['id'], 'name': orgRow['name'], 'code': orgRow['code'], 'logo': null};
    await _save();
  }

  Future<void> approvedAs({required String role, required String apiToken}) async {
    token = apiToken;
    session = {...?session, 'role': role, 'status': 'approved', 'loggedInAt': nowIso()};
    await _save();
  }

  Future<void> setStatus(String status) async {
    session = {...?session, 'status': status};
    await _save();
  }

  /// Organization settings (name, logo, alert days, low-stock level) as agreed through the sheet.
  Future<void> applySettings(Map<String, dynamic> s) async {
    org = {
      ...?org,
      if (s['name'] != null) 'name': s['name'],
      'logo': s['logo'],
    };
    await _save();
  }

  Future<void> setRoles(List<String> r) async {
    session = {...?session, 'roles': r};
    await _save();
  }

  Future<void> setBranch(String id) async {
    session = {...?session, 'branch': id};
    await _save();
  }

  Future<void> setName(String name) async {
    session = {...?session, 'name': name.trim()};
    await _save();
  }

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await Db.instance.setKv('theme', m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system');
    notifyListeners();
  }

  Future<void> setAutoBackup(bool v) async {
    autoBackup = v;
    await Db.instance.setKv('auto_backup', v ? '1' : '0');
    notifyListeners();
  }

  /// Logs out and removes this organization's records from the phone, so the next person who uses this phone can never see
  /// them. (The spreadsheet and the other phones keep their copies.)
  Future<void> logout() async {
    final id = orgId;
    if (id.isNotEmpty) await Db.instance.wipeOrg(id);
    for (final k in ['session', 'org', 'sheet_url', 'api_token', 'last_rev', 'last_sync', 'users_cache', 'last_auto_backup', 'auto_backup_pw']) {
      await Db.instance.setKv(k, null);
    }
    session = null;
    org = null;
    sheetUrl = '';
    token = '';
    notifyListeners();
  }
}
