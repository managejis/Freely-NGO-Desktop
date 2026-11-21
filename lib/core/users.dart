import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'app_state.dart';
import 'cloud.dart';
import 'db.dart';

/// The organization's users and phones, kept in the Users / Devices tabs of the Google Sheet. Only the admin can read them
/// (cached on the admin's phone for offline use).
class Users {
  /// Number of phones waiting for approval (shown as a badge on the admin dashboard).
  static final ValueNotifier<int> pending = ValueNotifier(0);

  static Future<Map<String, dynamic>> cached() async {
    final s = await Db.instance.getKv('users_cache');
    if (s == null) return {'users': <dynamic>[], 'devices': <dynamic>[]};
    return Map<String, dynamic>.from(jsonDecode(s) as Map);
  }

  /// Loads the latest lists from the sheet (admin only, needs internet).
  static Future<Map<String, dynamic>> refresh() async {
    if (!AppState.instance.isAdmin || AppState.instance.isLocal) return cached();
    final r = await Sheets.authed('users');
    final data = {'users': r['users'], 'devices': r['devices'], 'orgCode': r['orgCode']};
    await Db.instance.setKv('users_cache', jsonEncode(data));
    _count(data);
    return data;
  }

  static void _count(Map<String, dynamic> data) {
    pending.value = ((data['devices'] as List?) ?? const []).where((d) => (d as Map)['status'] == 'pending').length;
  }

  static Future<void> loadCount() async => _count(await cached());

  /// Approved users (not the admin).
  static Future<List<Map<String, dynamic>>> approvedUsers() async {
    final c = await cached();
    return [
      for (final u in (c['users'] as List))
        if ((u as Map)['role'] == 'user' && u['status'] == 'approved') Map<String, dynamic>.from(u),
    ];
  }

  static Future<void> approve(String deviceId) async {
    await Sheets.authed('approve', {'deviceId': deviceId});
    await refresh();
  }

  static Future<void> reject(String deviceId) async {
    await Sheets.authed('reject', {'deviceId': deviceId});
    await refresh();
  }

  static Future<void> setStatus(String mobile, String status) async {
    await Sheets.authed('setUserStatus', {'targetMobile': mobile, 'status': status});
    await refresh();
  }

  static Future<void> setRoles(String mobile, List<String> roles) async {
    await Sheets.authed('setRoles', {'targetMobile': mobile, 'roles': roles});
    await refresh();
  }

  static Future<void> setBranch(String mobile, String branchId) async {
    await Sheets.authed('setBranch', {'targetMobile': mobile, 'branch': branchId});
    await refresh();
  }

  static Future<void> forceLogoutAll() async {
    await Sheets.authed('forceLogout');
    await refresh();
  }
}
