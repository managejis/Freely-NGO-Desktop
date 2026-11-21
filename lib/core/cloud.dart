import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_state.dart';

class SheetsError implements Exception {
  final String message, code, status;
  SheetsError(this.message, {this.code = 'ERR', this.status = ''});
  @override
  String toString() => message;
}

/// The organization's Google Sheet, reached through the Apps Script web app the admin deployed.
/// Nothing else is online: no Supabase, no other server.
class Sheets {
  static final _urlPattern = RegExp(r'^https://script\.google\.com/.+/exec$');
  static bool validUrl(String s) => _urlPattern.hasMatch(s.trim());

  /// Posts JSON to the web app. Apps Script answers a POST with a redirect to the real result, which must be fetched with GET.
  static Future<Map<String, dynamic>> call(String url, Map<String, dynamic> body) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', Uri.parse(url))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode(body);
      var res = await http.Response.fromStream(await client.send(req).timeout(const Duration(seconds: 90)));
      var hops = 0;
      while ({301, 302, 303, 307, 308}.contains(res.statusCode) && res.headers['location'] != null && hops++ < 5) {
        res = await client.get(Uri.parse(res.headers['location']!)).timeout(const Duration(seconds: 90));
      }
      if (res.statusCode != 200) throw SheetsError('The spreadsheet service answered with error ${res.statusCode}. Check the web app URL and that access is set to "Anyone".');
      final Map<String, dynamic> j;
      try {
        j = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      } catch (_) {
        throw SheetsError('The spreadsheet service did not answer correctly. Check the web app URL and that access is set to "Anyone".');
      }
      if (j['ok'] != true) throw SheetsError((j['error'] ?? 'Unknown error').toString(), code: (j['code'] ?? 'ERR').toString(), status: (j['status'] ?? '').toString());
      return j;
    } finally {
      client.close();
    }
  }

  /// A call made by an approved phone: adds the mobile number, device id and secret token.
  static Future<Map<String, dynamic>> authed(String action, [Map<String, dynamic> extra = const {}]) {
    final app = AppState.instance;
    return call(app.sheetUrl, {'action': action, 'mobile': app.mobile, 'deviceId': app.deviceId, 'token': app.token, ...extra});
  }

  // ---------------------------------------------------------------- invite code / admin key (short strings built from the URL)
  static String? deploymentId(String url) => RegExp(r'/s/([^/]+)/exec').firstMatch(url)?.group(1);
  static String urlFromId(String id) => 'https://script.google.com/macros/s/$id/exec';

  /// What the admin gives to users: "<org code>.<web app id>".
  static String invite(String orgCode, String url) => '$orgCode.${deploymentId(url) ?? ''}';

  static ({String code, String url})? parseInvite(String s) {
    final t = s.trim();
    final i = t.indexOf('.');
    if (i < 3 || i == t.length - 1) return null;
    return (code: t.substring(0, i).toUpperCase(), url: urlFromId(t.substring(i + 1)));
  }

  /// What the admin keeps to recover the organization on a new phone: "<secret token>.<web app id>".
  static String adminKey(String token, String url) => '$token.${deploymentId(url) ?? ''}';

  static ({String token, String url})? parseAdminKey(String s) {
    final t = s.trim();
    final i = t.indexOf('.');
    if (i < 10 || i == t.length - 1) return null;
    return (token: t.substring(0, i), url: urlFromId(t.substring(i + 1)));
  }

  /// Readable text for the errors people can run into.
  static String explain(Object e) {
    if (e is SheetsError) return e.message;
    if (e is TimeoutException) return 'The spreadsheet service is slow to answer. Please try again.';
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('ClientException') || s.contains('Failed host lookup')) {
      return 'No internet connection. Please try again when you are online.';
    }
    return s.replaceFirst('Exception: ', '');
  }
}
