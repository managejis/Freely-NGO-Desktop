import 'app_state.dart';

/// Role-based access control. A person can hold several roles; the admin (the NGO's Super Admin) holds everything.
/// The same matrix is enforced by the spreadsheet script (google-apps-script/Code.gs), so a phone never receives records its
/// roles may not read, and the sheet refuses writes the roles may not make. On top of the roles, a person can be assigned to ONE
/// branch: then the phone only ever receives and writes that branch's records.
const roleLabels = <String, String>{
  'ngo_admin': 'NGO Administrator',
  'home_manager': 'Home Manager',
  'children_coordinator': 'Children Home Coordinator',
  'oldage_coordinator': 'Old Age Home Coordinator',
  'patient_coordinator': 'Patient Care Coordinator',
  'doctor': 'Doctor / Medical Staff',
  'accountant': 'Accountant',
  'caretaker': 'Caretaker',
  'volunteer': 'Volunteer',
  'auditor': 'Auditor (read-only)',
};

const _exec = {'ngo_admin'};
const _mgr = {'ngo_admin', 'home_manager'};
const _coord = {'children_coordinator', 'oldage_coordinator', 'patient_coordinator'};
const _care = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'doctor', 'volunteer'};
const _medical = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'doctor'};
const _safe = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator'};
const _money = {'ngo_admin', 'home_manager', 'accountant'};
const _moneyRead = {'ngo_admin', 'home_manager', 'accountant', 'auditor'};
const _stockWrite = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'doctor'};
const _stockRead = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'doctor', 'accountant', 'auditor'};
const _attRead = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'auditor'};
const _attWrite = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker'};
const _expenseEnter = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'accountant'};
const _beneficiaryRead = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'caretaker', 'doctor', 'volunteer', 'auditor'};
const _beneficiaryWrite = {'ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator'};
/// Roles that see every beneficiary category. A person who only holds a coordinator role sees only their own category.
const _broad = {'ngo_admin', 'home_manager', 'doctor', 'auditor', 'caretaker', 'volunteer', 'accountant'};
const _coordCategory = {'children_coordinator': 'child', 'oldage_coordinator': 'elder', 'patient_coordinator': 'patient'};

/// Record type -> roles that may read / write it (the admin is always allowed). `null` = everybody.
const _read = <String, Set<String>?>{
  'branch': null, 'beneficiary': _beneficiaryRead, 'medical': _medical, 'safeguard': _safe, 'care': _care, 'attendance': _attRead,
  'person': {'ngo_admin', 'home_manager', 'auditor'}, 'leave': {'ngo_admin', 'home_manager', 'auditor'}, 'donation': _moneyRead, 'expense': _moneyRead, 'item': _stockRead, 'stock': _stockRead,
  'announcement': null, 'settings': null, 'audit': null,
};
const _write = <String, Set<String>?>{
  'branch': <String>{}, 'beneficiary': _beneficiaryWrite, 'medical': _medical, 'safeguard': _safe, 'care': _care, 'attendance': _attWrite,
  'person': _mgr, 'leave': null, 'donation': _money, 'expense': _expenseEnter, 'item': _mgr, 'stock': _stockWrite,
  'announcement': _mgr, 'settings': <String>{}, 'audit': null,
};

class Perms {
  static AppState get _a => AppState.instance;

  static bool _has(Set<String>? allowed) {
    if (_a.isAdmin) return true;
    if (allowed == null) return true;
    return _a.roles.any(allowed.contains);
  }

  static bool hasRole(Set<String> r) => _a.isAdmin || _a.roles.any(r.contains);

  static bool canRead(String type) => _has(_read[type]);
  static bool canWrite(String type) => _has(_write[type]);

  static bool get beneficiaries => canRead('beneficiary');
  static bool get editBeneficiaries => canWrite('beneficiary');
  static bool get medical => canRead('medical');
  static bool get writeMedical => canWrite('medical');
  static bool get safeguard => canRead('safeguard');
  static bool get writeSafeguard => canWrite('safeguard');
  static bool get care => canRead('care');
  static bool get writeCare => canWrite('care');
  static bool get attendance => canRead('attendance');
  static bool get takeAttendance => canWrite('attendance');
  static bool get people => canRead('person');
  static bool get editPeople => canWrite('person');
  /// Everybody may request leave; managers and auditors see everybody's leave, others only their own requests.
  static bool get leaveAll => canRead('leave');
  static bool get donations => canRead('donation');
  static bool get editDonations => canWrite('donation');
  static bool get expenses => canRead('expense');
  static bool get enterExpenses => canWrite('expense');
  static bool get inventory => canRead('item');
  static bool get editItems => canWrite('item');
  static bool get stockMoves => canWrite('stock');
  static bool get editAnnouncements => canWrite('announcement');
  static bool get manageUsers => _a.isAdmin;
  static bool get finance => donations || expenses;
  static bool get reports => beneficiaries || finance || inventory || attendance;

  /// Expense workflow: the manager verifies, the administrator approves, the accountant records the payment.
  static bool get verifyExpense => _a.isAdmin || hasRole(const {'ngo_admin', 'home_manager'});
  static bool get approveExpense => _a.isAdmin || hasRole(_exec);
  static bool get payExpense => _a.isAdmin || hasRole(const {'accountant'});
  /// Can move stock between branches (needs access to every branch).
  static bool get transferStock => _a.branch.isEmpty && hasRole(const {'ngo_admin'});

  /// Beneficiary categories this person may see, or null for all of them.
  static Set<String>? get categories {
    if (_a.isAdmin || _a.roles.any(_broad.contains)) return null;
    final c = {for (final r in _a.roles) if (_coordCategory[r] != null) _coordCategory[r]!};
    return c.isEmpty ? null : c;
  }

  static List<String> get allowedCategories => (categories ?? const {'child', 'elder', 'patient'}).toList()..sort();

  static String rolesText(List<String> r) => r.isEmpty ? 'No role' : r.map((x) => roleLabels[x] ?? x).join(', ');

  static bool get isCoordinatorOnly => _a.roles.any(_coord.contains) && categories != null;
}
