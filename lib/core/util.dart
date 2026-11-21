import 'dart:math';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
String nowIso() => DateTime.now().toUtc().toIso8601String();

String _two(int n) => n.toString().padLeft(2, '0');
String dateStr(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
DateTime? parseDate(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s);
DateTime today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-11-18" -> "18 Nov 2026"
String fmtDate(String? s) {
  final d = parseDate(s);
  if (d == null) return '-';
  return '${_two(d.day)} ${_months[d.month - 1]} ${d.year}';
}

/// ISO timestamp (UTC) -> local "18 Nov 2026, 14:05"
String fmtDateTime(String? iso) {
  final d = parseDate(iso)?.toLocal();
  if (d == null) return 'never';
  return '${_two(d.day)} ${_months[d.month - 1]} ${d.year}, ${_two(d.hour)}:${_two(d.minute)}';
}

String fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

int daysBetween(DateTime a, DateTime b) => DateTime(b.year, b.month, b.day).difference(DateTime(a.year, a.month, a.day)).inDays;

String randomCode(int n) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}

/// Mobile numbers are compared as plain digits (a leading 91 / 0 is dropped when it gives a 10-digit Indian number).
String normMobile(String s) {
  var d = s.replaceAll(RegExp(r'\D'), '');
  if (d.length == 12 && d.startsWith('91')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = d.substring(1);
  return d;
}

bool validMobile(String s) => RegExp(r'^\d{10}$').hasMatch(normMobile(s));
