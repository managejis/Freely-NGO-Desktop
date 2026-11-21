import 'app_state.dart';
import 'db.dart';
import 'perms.dart';
import 'sync.dart';
import 'util.dart';

// ---------------------------------------------------------------------- record types
const tBranch = 'branch';            // a home / care centre / service location
const tBeneficiary = 'beneficiary';  // child, elderly resident or patient (core record, no medical details)
const tMedical = 'medical';          // restricted: health records, medication, diagnosis
const tSafeguard = 'safeguard';      // restricted: incidents, safeguarding concerns, death records
const tCare = 'care';                // daily care, activities, visits, education, nutrition ...
const tAttendance = 'attendance';
const tPerson = 'person';            // staff and volunteers
const tLeave = 'leave';              // leave request of a staff member or volunteer
const tDonation = 'donation';
const tExpense = 'expense';
const tItem = 'item';                // inventory item
const tStock = 'stock';              // inventory stock transaction (balance = sum of these)
const tAnnouncement = 'announcement';
const tAudit = 'audit';
const tSettings = 'settings';
const entityTypes = {tBranch, tBeneficiary, tMedical, tSafeguard, tCare, tAttendance, tPerson, tLeave, tDonation, tExpense, tItem, tStock, tAnnouncement, tAudit, tSettings};

/// Types where the newest write simply wins (no conflict dialog).
const lastWriterWinsTypes = {tAudit, tSettings};

/// Types that belong to a branch (a branch manager only ever sees / writes their own branch).
const branchScopedTypes = {tBeneficiary, tMedical, tSafeguard, tCare, tAttendance, tPerson, tLeave, tDonation, tExpense, tItem, tStock};

// ---------------------------------------------------------------------- lists
const catChild = 'child', catElder = 'elder', catPatient = 'patient';
const categoryLabels = {catChild: 'Child', catElder: 'Old age resident', catPatient: 'Patient'};
const categoryPlural = {catChild: 'Children', catElder: 'Residents', catPatient: 'Patients'};
const categoryPrefix = {catChild: 'CH', catElder: 'OA', catPatient: 'PT'};

const branchKinds = ['Children Home', 'Old Age Home', 'Patient Care Centre', 'Other'];
const genders = ['Male', 'Female', 'Other'];
const beneficiaryStatuses = ['Active', 'Discharged', 'Transferred', 'Deceased'];
const personKinds = ['Staff', 'Volunteer'];
const personStatuses = ['Active', 'On leave', 'Left'];

const medicalKinds = ['Health check-up', 'Vaccination', 'Height / weight', 'Blood pressure / sugar', 'Medication given', 'Doctor consultation', 'Hospital visit', 'Diagnosis / treatment', 'Medical history', 'Other'];
const careKinds = ['Daily observation', 'School / education', 'Study hours', 'Sports / recreation', 'Counselling', 'Food / nutrition', 'Clothing / belongings', 'Personal care', 'Exercise', 'Family visit', 'Visitor', 'Home visit', 'Medical support', 'Financial support', 'Equipment distribution', 'Progress report', 'Special event', 'Other'];
const safeguardKinds = ['Incident', 'Safeguarding concern', 'Death record'];

const attendanceGroups = {catChild: 'Children', catElder: 'Residents', 'staff': 'Staff', 'volunteer': 'Volunteers'};
const attendanceStatuses = ['Present', 'Absent', 'On leave', 'Hospitalized', 'Home visit', 'Permission', 'Other'];

const donationTypes = ['Cash', 'Bank transfer', 'Food', 'Clothing', 'Medicine', 'Educational materials', 'Other material'];
const moneyDonationTypes = {'Cash', 'Bank transfer'};
const paymentModes = ['Cash', 'Bank', 'UPI / online', 'Cheque'];
const expenseCategories = ['Food and groceries', 'Medical expenses', 'Education expenses', 'Staff salaries', 'Rent', 'Electricity and utilities', 'Transportation', 'Building maintenance', 'Clothing', 'Other expenses'];
const inventoryCategories = ['Food and groceries', 'Medicines', 'Clothing', 'Educational materials', 'Medical equipment', 'Furniture', 'Cleaning supplies', 'Other materials'];
const stockKinds = {'in': 'Stock in', 'issue': 'Issue', 'adjust': 'Adjustment', 'out': 'Transfer out', 'recv': 'Transfer in'};

/// Expense workflow: entered -> verified (manager) -> approved (administrator) -> paid (accountant). A rejected expense is closed.
const expenseFlow = ['entered', 'verified', 'approved', 'paid'];
const expenseStatusLabels = {'entered': 'Entered', 'verified': 'Verified', 'approved': 'Approved', 'paid': 'Paid', 'rejected': 'Rejected'};

/// Leave: requested -> verified (manager) -> approved (administrator); or rejected / cancelled.
const leaveTypes = ['Casual leave', 'Sick leave', 'Earned leave', 'Unpaid leave', 'Other'];
const leaveFlow = ['requested', 'verified', 'approved'];
const leaveStatusLabels = {'requested': 'Requested', 'verified': 'Verified', 'approved': 'Approved', 'rejected': 'Rejected', 'cancelled': 'Cancelled'};
/// Days a person may take per financial year (April - March). Unpaid and other leave are not limited.
const leaveEntitlement = {'Casual leave': 12, 'Sick leave': 12, 'Earned leave': 15};

double r2(num v) => (v * 100).round() / 100;

/// 1234567.5 -> "12,34,567.50" (Indian digit grouping).
String money(num v) {
  final neg = v < 0;
  final parts = v.abs().toStringAsFixed(2).split('.');
  var i = parts[0];
  if (i.length > 3) {
    final last3 = i.substring(i.length - 3);
    var rest = i.substring(0, i.length - 3);
    final g = <String>[];
    while (rest.length > 2) {
      g.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) g.insert(0, rest);
    i = '${g.join(',')},$last3';
  }
  return '${neg ? '-' : ''}$i.${parts[1]}';
}

double amountOf(Rec t) => ((t.data['amount'] ?? 0) as num).toDouble();

int? ageOf(String? dob) {
  final d = parseDate(dob);
  if (d == null) return null;
  final n = today();
  var a = n.year - d.year;
  if (n.month < d.month || (n.month == d.month && n.day < d.day)) a--;
  return a < 0 ? null : a;
}

/// Records are always read from / written to the phone first. The sync engine copies them to the Google Sheet later.
class Store {
  static Db get _db => Db.instance;
  static AppState get _app => AppState.instance;

  static String get me => _app.mobile;

  static Future<List<Rec>> list(String type) => _db.list(_app.orgId, type);

  /// Only the records of the user's own branch (users without a branch see everything their roles allow).
  static List<Rec> _inBranch(List<Rec> l) {
    final b = _app.branch;
    return b.isEmpty ? l : l.where((r) => r.s('branchId').isEmpty || r.s('branchId') == b).toList();
  }

  static List<Rec> _inCategory(List<Rec> l, String key) {
    final c = Perms.categories;
    return c == null ? l : l.where((r) => c.contains(r.s(key))).toList();
  }

  // ------------------------------------------------------------------ branches
  static Future<List<Rec>> branches() async {
    final r = await list(tBranch);
    r.sort((a, b) => a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase()));
    return r;
  }

  static Map<String, String> _branchNames = {};
  static Future<void> loadBranchNames() async => _branchNames = {for (final b in await branches()) b.id: b.s('name')};
  static String branchName(String id) => id.isEmpty ? 'All branches' : (_branchNames[id] ?? 'Unknown branch');

  // ------------------------------------------------------------------ beneficiaries
  static Future<List<Rec>> beneficiaries({String? category, String? branchId}) async {
    var r = _inCategory(_inBranch(await list(tBeneficiary)), 'category');
    if (category != null) r = r.where((x) => x.s('category') == category).toList();
    if (branchId != null && branchId.isNotEmpty) r = r.where((x) => x.s('branchId') == branchId).toList();
    r.sort((a, b) => a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase()));
    return r;
  }

  static String newBeneficiaryId(String category) => '${categoryPrefix[category] ?? 'BN'}-${randomCode(6)}';

  static Future<List<Rec>> forBeneficiary(String type, String beneficiaryId) async {
    final r = (await list(type)).where((e) => e.s('beneficiaryId') == beneficiaryId).toList();
    r.sort((a, b) => b.s('date').compareTo(a.s('date')));
    return r;
  }

  static Future<List<Rec>> medical() async => _inCategory(_inBranch(await list(tMedical)), 'category');
  static Future<List<Rec>> care() async => _inCategory(_inBranch(await list(tCare)), 'category');
  static Future<List<Rec>> safeguards() async => _inCategory(_inBranch(await list(tSafeguard)), 'category');

  // ------------------------------------------------------------------ people (staff and volunteers)
  static Future<List<Rec>> people({String? kind}) async {
    var r = _inBranch(await list(tPerson));
    if (kind != null) r = r.where((x) => x.s('kind') == kind).toList();
    r.sort((a, b) => a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase()));
    return r;
  }

  // ------------------------------------------------------------------ attendance
  /// One attendance sheet per day, branch and group, so the same id is used by everyone who records it.
  static String attendanceId(String date, String branchId, String group) => 'att-$date-$branchId-$group';

  static Future<List<Rec>> attendance() async {
    final r = _inBranch(await list(tAttendance));
    r.sort((a, b) => b.s('date').compareTo(a.s('date')));
    return r;
  }

  // ------------------------------------------------------------------ leave
  static Future<List<Rec>> leaves() async {
    final r = _inBranch(await list(tLeave));
    r.sort((a, b) => b.s('fromDate').compareTo(a.s('fromDate')));
    return r;
  }

  static String leaveStatus(Rec l) => l.s('status').isEmpty ? 'requested' : l.s('status');

  /// Inclusive number of days from [from] to [to] (yyyy-MM-dd).
  static int leaveDays(String from, String to) {
    final a = parseDate(from), b = parseDate(to);
    return (a == null || b == null || b.isBefore(a)) ? 0 : daysBetween(a, b) + 1;
  }

  /// Financial year (April - March) a date falls in, as its starting year.
  static int fyOf(DateTime d) => d.month >= 4 ? d.year : d.year - 1;

  /// Approved days of [type] already used by the person who made the requests in [list], in financial year [fy].
  static int usedLeave(List<Rec> list, String type, int fy, {String? ignoreId}) {
    var n = 0;
    for (final l in list) {
      if (l.id == ignoreId || leaveStatus(l) != 'approved' || l.s('leaveType') != type) continue;
      final d = parseDate(l.s('fromDate'));
      if (d != null && fyOf(d) == fy) n += l.i('days');
    }
    return n;
  }

  static Future<void> advanceLeave(Rec l, String to) {
    final who = {'verified': 'verifiedBy', 'approved': 'approvedBy', 'rejected': 'rejectedBy', 'cancelled': 'cancelledBy'}[to]!;
    return save(tLeave, id: l.id, summary: 'Leave ${l.s('personName')} ${l.s('fromDate')}..${l.s('toDate')} -> ${leaveStatusLabels[to]}', data: {
      ...l.data, 'status': to, who: _app.mobile, '${who}At': nowIso(),
    });
  }

  /// Approved leave that covers [date]: used to pre-fill "On leave" when staff attendance is taken.
  static Future<List<Rec>> approvedLeaveOn(String date) async =>
      (await leaves()).where((l) => leaveStatus(l) == 'approved' && l.s('fromDate').compareTo(date) <= 0 && l.s('toDate').compareTo(date) >= 0).toList();

  // ------------------------------------------------------------------ money
  static Future<List<Rec>> donations() async {
    final r = _inBranch(await list(tDonation));
    r.sort((a, b) => b.s('date').compareTo(a.s('date')));
    return r;
  }

  static Future<List<Rec>> expenses() async {
    final r = _inBranch(await list(tExpense));
    r.sort((a, b) => b.s('date').compareTo(a.s('date')));
    return r;
  }

  static bool isVoid(Rec t) => t.data['void'] == true;

  /// Donations and expenses are never deleted: they are voided with a reason and stay visible (struck through) for the audit.
  static Future<void> voidRec(Rec t, String reason, String what) => save(t.type,
      id: t.id,
      data: {...t.data, 'void': true, 'voidReason': reason, 'voidedBy': _app.mobile, 'voidedAt': nowIso()},
      summary: 'Voided $what ${money(amountOf(t))}: $reason');

  static String expenseStatus(Rec e) => e.s('status').isEmpty ? 'entered' : e.s('status');

  /// Moves an expense one step forward (or rejects it) and keeps who did it.
  static Future<void> advanceExpense(Rec e, String to) {
    final who = {'verified': 'verifiedBy', 'approved': 'approvedBy', 'paid': 'paidBy', 'rejected': 'rejectedBy'}[to]!;
    return save(tExpense, id: e.id, summary: 'Expense ${money(amountOf(e))} ${e.s('category')} -> ${expenseStatusLabels[to]}', data: {
      ...e.data, 'status': to, who: _app.mobile, '${who}At': nowIso(),
    });
  }

  // ------------------------------------------------------------------ inventory (balance = sum of stock transactions)
  static Future<List<Rec>> items() async {
    final r = _inBranch(await list(tItem));
    r.sort((a, b) => a.s('name').toLowerCase().compareTo(b.s('name').toLowerCase()));
    return r;
  }

  static Future<List<Rec>> stockTx() async => _inBranch(await list(tStock));

  static Map<String, double> balances(List<Rec> tx) {
    final m = <String, double>{};
    for (final t in tx) {
      m[t.s('itemId')] = r2((m[t.s('itemId')] ?? 0) + ((t.data['qty'] ?? 0) as num).toDouble());
    }
    return m;
  }

  static double minStockOf(Rec item) => ((item.data['minStock'] ?? 0) as num).toDouble();

  // ------------------------------------------------------------------ announcements
  static Future<List<Rec>> announcements() async {
    final r = await list(tAnnouncement);
    r.sort((a, b) {
      final e = (b.data['urgent'] == true ? 1 : 0) - (a.data['urgent'] == true ? 1 : 0);
      return e != 0 ? e : b.s('date').compareTo(a.s('date'));
    });
    return r;
  }

  // ------------------------------------------------------------------ writing
  /// Creates (id == null) or edits a record. Saved on the phone first and marked for upload to the sheet.
  static Future<Rec> save(String type, {String? id, required Map<String, dynamic> data, String? summary, bool audit = true}) async {
    final me = _app.mobile;
    final existing = id == null ? null : await _db.get(id);
    final Rec rec;
    if (existing != null) {
      existing.edit(by: me, newData: data, isDeleted: existing.deleted ? false : null);
      rec = existing;
    } else {
      rec = Rec(id: id ?? newId(), orgId: _app.orgId, type: type, data: data, updatedAt: nowIso(), by: me);
    }
    rec.dirty = !_app.isLocal;
    await _db.put(rec);
    if (audit && summary != null) await _audit(existing == null ? 'created' : 'edited', type, rec.id, summary);
    SyncEngine.instance.trigger();
    return rec;
  }

  static Future<void> remove(Rec r, String summary) async {
    r.edit(by: _app.mobile, isDeleted: true);
    r.dirty = !_app.isLocal;
    await _db.put(r);
    await _audit('deleted', r.type, r.id, summary);
    SyncEngine.instance.trigger();
  }

  static Future<void> _audit(String action, String type, String targetId, String summary) async {
    final rec = Rec(
      id: newId(), orgId: _app.orgId, type: tAudit, updatedAt: nowIso(), by: _app.mobile,
      data: {'action': action, 'entity': type, 'targetId': targetId, 'summary': summary, 'by': _app.mobile, 'at': nowIso()},
    )..dirty = !_app.isLocal;
    await _db.put(rec);
  }

  static Future<void> audit(String action, String type, String targetId, String summary) => _audit(action, type, targetId, summary);

  /// Reading sensitive records (medical, safeguarding) is itself audited, as the requirements ask.
  static Future<void> auditAccess(String type, String targetId, String summary) => _audit('viewed', type, targetId, summary);

  static Future<List<Rec>> audits() async {
    final r = await list(tAudit);
    r.sort((a, b) => b.s('at').compareTo(a.s('at')));
    return r;
  }

  // ------------------------------------------------------------------ NGO settings (admin)
  static Future<void> saveSettings({String? name, String? logo, bool clearLogo = false}) async {
    final cur = <String, dynamic>{'name': name ?? _app.orgName, 'logo': clearLogo ? null : (logo ?? _app.logo)};
    await _app.applySettings(cur);
    await save(tSettings, id: 'settings-${_app.orgId}', data: cur, summary: 'NGO settings changed');
  }
}
