import 'package:flutter/material.dart';

import 'db.dart';
import 'perms.dart';
import 'store.dart';
import 'util.dart';

class ReportTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<String> footer;     // totals / notes shown under the table
  ReportTable(this.title, this.headers, this.rows, {this.footer = const []});
}

class ReportDef {
  final String key, title, subtitle;
  final IconData icon;
  final bool Function() allowed;
  final bool dated;
  final Future<ReportTable> Function(DateTimeRange? range, String branchId) build;
  const ReportDef(this.key, this.title, this.subtitle, this.icon, this.allowed, this.dated, this.build);
}

bool _in(String date, DateTimeRange? r) {
  if (r == null) return true;
  final d = parseDate(date.length >= 10 ? date.substring(0, 10) : date);
  if (d == null) return false;
  return !d.isBefore(DateTime(r.start.year, r.start.month, r.start.day)) && !d.isAfter(DateTime(r.end.year, r.end.month, r.end.day));
}

bool _br(Rec r, String branchId) => branchId.isEmpty || r.s('branchId') == branchId;
String _age(Rec b) => ageOf(b.s('dob'))?.toString() ?? '';
String _d(String s) => s.isEmpty ? '' : fmtDate(s);
String _amt(Rec r) => moneyDonationTypes.contains(r.s('type')) ? money(amountOf(r)) : r.s('quantity');

Future<List<Rec>> _beneficiaries(String branchId) async {
  await Store.loadBranchNames();
  return (await Store.beneficiaries()).where((b) => _br(b, branchId)).toList();
}

final List<ReportDef> allReports = [
  ReportDef('beneficiary', 'Beneficiary report', 'All active and inactive beneficiaries', Icons.groups_outlined, () => Perms.beneficiaries, false, (r, b) async {
    final l = await _beneficiaries(b);
    return ReportTable('Beneficiary report', ['ID', 'Name', 'Category', 'Gender', 'Age', 'Branch', 'Status', 'Admitted', 'Discharged'], [
      for (final x in l) [x.s('bid'), x.s('name'), categoryLabels[x.s('category')] ?? '', x.s('gender'), _age(x), Store.branchName(x.s('branchId')), x.s('status'), _d(x.s('admissionDate')), _d(x.s('dischargeDate'))],
    ], footer: ['Total: ${l.length}', 'Active: ${l.where((x) => x.s('status') == 'Active').length}']);
  }),
  ReportDef('admission', 'Admission report', 'New admissions and re-admissions', Icons.login, () => Perms.beneficiaries, true, (r, b) => _events(r, b, const {'Admitted', 'Re-admitted'}, 'Admission report')),
  ReportDef('discharge', 'Discharge report', 'Discharges and deaths', Icons.logout, () => Perms.beneficiaries, true, (r, b) => _events(r, b, const {'Discharged', 'Deceased'}, 'Discharge report')),
  ReportDef('attendance', 'Attendance report', 'Daily and monthly attendance', Icons.fact_check_outlined, () => Perms.attendance, true, (r, b) async {
    await Store.loadBranchNames();
    final l = (await Store.attendance()).where((a) => _in(a.s('date'), r) && _br(a, b)).toList()..sort((x, y) => x.s('date').compareTo(y.s('date')));
    final present = l.fold<int>(0, (a, x) => a + ((x.data['presentCount'] ?? 0) as num).toInt());
    final absent = l.fold<int>(0, (a, x) => a + ((x.data['absentCount'] ?? 0) as num).toInt());
    return ReportTable('Attendance report', ['Date', 'Branch', 'Group', 'Present', 'Not present'], [
      for (final x in l) [_d(x.s('date')), Store.branchName(x.s('branchId')), attendanceGroups[x.s('group')] ?? x.s('group'), '${x.data['presentCount'] ?? 0}', '${x.data['absentCount'] ?? 0}'],
    ], footer: ['Sheets: ${l.length}', 'Total present marks: $present', 'Total not present: $absent']);
  }),
  ReportDef('medical', 'Medical report', 'Medical history and follow-ups', Icons.medical_information_outlined, () => Perms.medical, true, (r, b) async {
    await Store.loadBranchNames();
    final l = (await Store.medical()).where((m) => _in(m.s('date'), r) && _br(m, b)).toList()..sort((x, y) => x.s('date').compareTo(y.s('date')));
    return ReportTable('Medical report', ['Date', 'Beneficiary', 'Category', 'Type', 'Value', 'Details', 'Next follow-up'], [
      for (final m in l) [_d(m.s('date')), m.s('beneficiaryName'), categoryLabels[m.s('category')] ?? '', m.s('kind'), m.s('value'), m.s('notes'), _d(m.s('nextFollowUp'))],
    ], footer: ['Records: ${l.length}']);
  }),
  ReportDef('leave', 'Leave report', 'Leave requests, approvals and days taken', Icons.event_busy_outlined, () => Perms.leaveAll, true, (r, b) async {
    await Store.loadBranchNames();
    bool overlaps(Rec l) {
      if (r == null) return true;
      final a = parseDate(l.s('fromDate')), c = parseDate(l.s('toDate'));
      if (a == null || c == null) return false;
      return !c.isBefore(DateTime(r.start.year, r.start.month, r.start.day)) && !a.isAfter(DateTime(r.end.year, r.end.month, r.end.day));
    }
    final l = (await Store.leaves()).where((x) => overlaps(x) && _br(x, b)).toList()..sort((x, y) => x.s('fromDate').compareTo(y.s('fromDate')));
    final approved = l.where((x) => Store.leaveStatus(x) == 'approved').fold<int>(0, (a, x) => a + x.i('days'));
    return ReportTable('Leave report', ['From', 'To', 'Days', 'Person', 'Type', 'Status', 'Branch', 'Reason'], [
      for (final x in l) [_d(x.s('fromDate')), _d(x.s('toDate')), '${x.i('days')}', x.s('personName'), x.s('leaveType'), leaveStatusLabels[Store.leaveStatus(x)] ?? '', Store.branchName(x.s('branchId')), x.s('reason')],
    ], footer: ['Requests: ${l.length}', 'Approved days: $approved']);
  }),
  ReportDef('donation', 'Donation report', 'All donations in the period', Icons.volunteer_activism_outlined, () => Perms.donations, true, (r, b) async {
    await Store.loadBranchNames();
    final l = (await Store.donations()).where((d) => !Store.isVoid(d) && _in(d.s('date'), r) && _br(d, b)).toList()..sort((x, y) => x.s('date').compareTo(y.s('date')));
    final total = l.where((d) => moneyDonationTypes.contains(d.s('type'))).fold(0.0, (a, d) => a + amountOf(d));
    return ReportTable('Donation report', ['Date', 'Receipt', 'Donor', 'Type', 'Amount / quantity', 'Mode', 'Purpose', 'Branch'], [
      for (final d in l) [_d(d.s('date')), d.s('receiptNo'), d.s('donor'), d.s('type'), _amt(d), d.s('mode'), '${d.s('purpose')}${d.data['restricted'] == true ? ' (restricted)' : ''}', Store.branchName(d.s('branchId'))],
    ], footer: ['Entries: ${l.length}', 'Cash + bank total: ${money(total)}']);
  }),
  ReportDef('donor', 'Donor-wise report', 'Contribution of each donor', Icons.people_outline, () => Perms.donations, true, (r, b) async {
    final l = (await Store.donations()).where((d) => !Store.isVoid(d) && _in(d.s('date'), r) && _br(d, b)).toList();
    final m = <String, ({int n, double amt, int material})>{};
    for (final d in l) {
      final k = d.s('donor').trim();
      final o = m[k] ?? (n: 0, amt: 0.0, material: 0);
      final cash = moneyDonationTypes.contains(d.s('type'));
      m[k] = (n: o.n + 1, amt: o.amt + (cash ? amountOf(d) : 0), material: o.material + (cash ? 0 : 1));
    }
    final keys = m.keys.toList()..sort((a, c) => m[c]!.amt.compareTo(m[a]!.amt));
    return ReportTable('Donor-wise report', ['Donor', 'Donations', 'Cash + bank total', 'Material gifts'], [for (final k in keys) [k, '${m[k]!.n}', money(m[k]!.amt), '${m[k]!.material}']],
        footer: ['Donors: ${keys.length}', 'Total: ${money(keys.fold(0.0, (a, k) => a + m[k]!.amt))}']);
  }),
  ReportDef('expense', 'Expense report', 'Category-wise expenses by approval status', Icons.receipt_long_outlined, () => Perms.expenses, true, (r, b) async {
    final l = (await Store.expenses()).where((e) => !Store.isVoid(e) && _in(e.s('date'), r) && _br(e, b)).toList();
    final cats = <String, List<double>>{};
    for (final e in l) {
      final st = Store.expenseStatus(e);
      if (st == 'rejected') continue;
      final v = cats.putIfAbsent(e.s('category'), () => [0, 0, 0]);
      v[st == 'paid' ? 2 : (st == 'approved' ? 1 : 0)] += amountOf(e);
    }
    final keys = cats.keys.toList()..sort();
    double col(int i) => keys.fold(0.0, (a, k) => a + cats[k]![i]);
    return ReportTable('Expense report', ['Category', 'Awaiting approval', 'Approved (unpaid)', 'Paid'], [for (final k in keys) [k, money(cats[k]![0]), money(cats[k]![1]), money(cats[k]![2])]],
        footer: ['Awaiting approval: ${money(col(0))}', 'Approved: ${money(col(1))}', 'Paid: ${money(col(2))}']);
  }),
  ReportDef('inventory', 'Inventory report', 'Current stock of every item', Icons.inventory_2_outlined, () => Perms.inventory, false, (r, b) async {
    await Store.loadBranchNames();
    final items = (await Store.items()).where((i) => _br(i, b)).toList();
    final bal = Store.balances(await Store.stockTx());
    String st(Rec i) {
      final d = parseDate(i.s('expiryDate'));
      if (d != null && daysBetween(today(), d) < 0) return 'Expired';
      if (d != null && daysBetween(today(), d) <= 30) return 'Expiring soon';
      return (bal[i.id] ?? 0) <= Store.minStockOf(i) ? 'Low stock' : 'OK';
    }
    return ReportTable('Inventory report', ['Item', 'Category', 'Branch', 'Balance', 'Unit', 'Minimum', 'Expiry', 'Status'], [
      for (final i in items) [i.s('name'), i.s('category'), Store.branchName(i.s('branchId')), '${bal[i.id] ?? 0}', i.s('unit'), '${Store.minStockOf(i)}', _d(i.s('expiryDate')), st(i)],
    ], footer: ['Items: ${items.length}', 'Needing attention: ${items.where((i) => st(i) != 'OK').length}']);
  }),
  ReportDef('staff', 'Staff report', 'Staff and volunteer details', Icons.badge_outlined, () => Perms.people, false, (r, b) async {
    await Store.loadBranchNames();
    final l = (await Store.people()).where((p) => _br(p, b)).toList();
    return ReportTable('Staff report', ['Name', 'Type', 'Designation', 'Department', 'Branch', 'Status', 'Joined', 'Phone'], [
      for (final p in l) [p.s('name'), p.s('kind'), p.s('designation'), p.s('department'), Store.branchName(p.s('branchId')), p.s('status'), _d(p.s('joinDate')), p.s('phone')],
    ], footer: ['Total: ${l.length}']);
  }),
  ReportDef('branch', 'Branch report', 'Facility-wise summary', Icons.apartment_outlined, () => Perms.beneficiaries, true, (r, b) async {
    await Store.loadBranchNames();
    final branches = (await Store.branches()).where((x) => b.isEmpty || x.id == b).toList();
    final ben = await Store.beneficiaries();
    final people = Perms.people ? await Store.people() : <Rec>[];
    final don = Perms.donations ? await Store.donations() : <Rec>[];
    final exp = Perms.expenses ? await Store.expenses() : <Rec>[];
    final rows = <List<String>>[];
    for (final x in branches) {
      final bb = ben.where((e) => e.s('branchId') == x.id && e.s('status') == 'Active').toList();
      rows.add([
        x.s('name'), x.s('kind'),
        '${bb.where((e) => e.s('category') == catChild).length}', '${bb.where((e) => e.s('category') == catElder).length}', '${bb.where((e) => e.s('category') == catPatient).length}',
        Perms.people ? '${people.where((p) => p.s('branchId') == x.id && p.s('status') == 'Active').length}' : '-',
        Perms.donations ? money(don.where((d) => !Store.isVoid(d) && d.s('branchId') == x.id && _in(d.s('date'), r) && moneyDonationTypes.contains(d.s('type'))).fold(0.0, (a, d) => a + amountOf(d))) : '-',
        Perms.expenses ? money(exp.where((e) => !Store.isVoid(e) && e.s('branchId') == x.id && Store.expenseStatus(e) == 'paid' && _in(e.s('date'), r)).fold(0.0, (a, e) => a + amountOf(e))) : '-',
      ]);
    }
    return ReportTable('Branch report', ['Branch', 'Type', 'Children', 'Residents', 'Patients', 'Staff', 'Donations (period)', 'Paid expenses (period)'], rows);
  }),
  ReportDef('visits', 'Patient visit report', 'Home visits and support to patients', Icons.home_work_outlined, () => Perms.care, true, (r, b) => _care(r, b, 'Patient visit report', onlyPatients: true)),
  ReportDef('activity', 'Activity report', 'Daily care and activities', Icons.volunteer_activism_outlined, () => Perms.care, true, (r, b) => _care(r, b, 'Activity report')),
];

Future<ReportTable> _events(DateTimeRange? r, String b, Set<String> events, String title) async {
  final l = await _beneficiaries(b);
  final rows = <(String, List<String>)>[];
  for (final x in l) {
    for (final h in (x.data['history'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(h as Map);
      if (events.contains(m['event']) && _in('${m['date']}', r)) {
        rows.add(('${m['date']}', [_d('${m['date']}'), x.s('bid'), x.s('name'), categoryLabels[x.s('category')] ?? '', Store.branchName('${m['branchId'] ?? x.s('branchId')}'), '${m['event']}', '${m['note'] ?? ''}']));
      }
    }
  }
  rows.sort((a, c) => a.$1.compareTo(c.$1));
  return ReportTable(title, ['Date', 'ID', 'Name', 'Category', 'Branch', 'Event', 'Note'], [for (final e in rows) e.$2], footer: ['Total: ${rows.length}']);
}

Future<ReportTable> _care(DateTimeRange? r, String b, String title, {bool onlyPatients = false}) async {
  await Store.loadBranchNames();
  final l = (await Store.care()).where((c) => _in(c.s('date'), r) && _br(c, b) && (!onlyPatients || c.s('category') == catPatient)).toList()..sort((x, y) => x.s('date').compareTo(y.s('date')));
  return ReportTable(title, ['Date', 'Name', 'Category', 'Type', 'Staff', 'Details', 'Next follow-up'], [
    for (final c in l) [_d(c.s('date')), c.s('beneficiaryName'), categoryLabels[c.s('category')] ?? '', c.s('kind'), c.s('staff'), c.s('notes'), _d(c.s('nextFollowUp'))],
  ], footer: ['Records: ${l.length}']);
}

/// Dashboard numbers.
class DashStats {
  int total = 0, children = 0, elders = 0, patients = 0, admissionsMonth = 0, dischargesMonth = 0, staff = 0, volunteers = 0;
  int onLeaveToday = 0, pendingLeave = 0;
  int presentToday = 0, sheetsToday = 0, followUps = 0, lowStock = 0, expirySoon = 0, pendingExpenses = 0;
  double donationsMonth = 0, expensesMonth = 0;
}

Future<DashStats> dashStats(String branchId) async {
  final s = DashStats();
  final now = today();
  final ym = dateStr(now).substring(0, 7);
  bool br(Rec r) => branchId.isEmpty || r.s('branchId') == branchId;
  if (Perms.beneficiaries) {
    final ben = (await Store.beneficiaries()).where(br).toList();
    final active = ben.where((b) => b.s('status') == 'Active').toList();
    s.total = active.length;
    s.children = active.where((b) => b.s('category') == catChild).length;
    s.elders = active.where((b) => b.s('category') == catElder).length;
    s.patients = active.where((b) => b.s('category') == catPatient).length;
    for (final b in ben) {
      for (final h in (b.data['history'] as List? ?? const [])) {
        final m = Map<String, dynamic>.from(h as Map);
        final d = '${m['date']}';
        if (!d.startsWith(ym)) continue;
        if (m['event'] == 'Admitted' || m['event'] == 'Re-admitted') s.admissionsMonth++;
        if (m['event'] == 'Discharged') s.dischargesMonth++;
      }
    }
  }
  if (Perms.people) {
    final p = (await Store.people()).where((x) => br(x) && x.s('status') == 'Active').toList();
    s.staff = p.where((x) => x.s('kind') == 'Staff').length;
    s.volunteers = p.where((x) => x.s('kind') == 'Volunteer').length;
  }
  if (Perms.attendance) {
    for (final a in (await Store.attendance()).where((a) => br(a) && a.s('date') == dateStr(now))) {
      s.sheetsToday++;
      s.presentToday += ((a.data['presentCount'] ?? 0) as num).toInt();
    }
  }
  if (Perms.leaveAll) {
    final lv = (await Store.leaves()).where(br).toList();
    final t = dateStr(now);
    s.onLeaveToday = lv.where((l) => Store.leaveStatus(l) == 'approved' && l.s('fromDate').compareTo(t) <= 0 && l.s('toDate').compareTo(t) >= 0).length;
    s.pendingLeave = lv.where((l) => {'requested', 'verified'}.contains(Store.leaveStatus(l))).length;
  }
  final horizon = dateStr(now.add(const Duration(days: 7)));
  bool due(Rec r) => r.s('nextFollowUp').isNotEmpty && r.data['followDone'] != true && r.s('nextFollowUp').compareTo(horizon) <= 0;
  if (Perms.care) s.followUps += (await Store.care()).where((c) => br(c) && due(c)).length;
  if (Perms.medical) s.followUps += (await Store.medical()).where((c) => br(c) && due(c)).length;
  if (Perms.donations) {
    s.donationsMonth = (await Store.donations()).where((d) => br(d) && !Store.isVoid(d) && d.s('date').startsWith(ym) && moneyDonationTypes.contains(d.s('type'))).fold(0.0, (a, d) => a + amountOf(d));
  }
  if (Perms.expenses) {
    final ex = (await Store.expenses()).where((e) => br(e) && !Store.isVoid(e)).toList();
    s.expensesMonth = ex.where((e) => e.s('date').startsWith(ym) && Store.expenseStatus(e) == 'paid').fold(0.0, (a, e) => a + amountOf(e));
    s.pendingExpenses = ex.where((e) => {'entered', 'verified', 'approved'}.contains(Store.expenseStatus(e))).length;
  }
  if (Perms.inventory) {
    final items = (await Store.items()).where(br).toList();
    final bal = Store.balances(await Store.stockTx());
    for (final i in items) {
      final d = parseDate(i.s('expiryDate'));
      if (d != null && daysBetween(now, d) <= 30) {
        s.expirySoon++;
      } else if ((bal[i.id] ?? 0) <= Store.minStockOf(i)) {
        s.lowStock++;
      }
    }
  }
  return s;
}
