/**
 * Freely NGO - spreadsheet API.  Paste this whole file into the Apps Script editor of YOUR Google Sheet
 * (Sheet > Extensions > Apps Script), then Deploy > New deployment > type "Web app":
 *     Execute as: Me          Who has access: Anyone
 * Google asks you ONCE to approve the permissions - that is the admin approval. Copy the Web app URL into the Freely NGO app.
 *
 * The spreadsheet is the organization's central copy of all data. Every phone keeps its own SQLite copy and syncs with this
 * script whenever the internet is on. Tabs (readable in Google Sheets, please edit data in the app, not here):
 *   Users, Devices, Branches, Beneficiaries, Medical, Safeguarding, Care, Attendance, Staff, Donations, Expenses, Inventory, StockLog,
 *   Leave, Announcements, AuditLog, Settings, Organization
 *
 * Security: phones identify themselves with a mobile number + a secret token that the admin approved. Only the hash of a token
 * is stored. Role-based access: a phone only receives (and may only write) the record types its user's roles allow, e.g. only the
 * accountant sees Donations and only doctors and coordinators see Medical records. A person assigned to a branch only sees that branch.
 */

var TYPES = {
  branch:       { tab: 'Branches',      cols: ['name', 'kind', 'address', 'phone', 'manager'] },
  beneficiary:  { tab: 'Beneficiaries', cols: ['bid', 'name', 'category', 'gender', 'dob', 'status', 'branchId', 'admissionDate', 'dischargeDate', 'phone', 'address', 'guardianName', 'guardianPhone', 'emergencyName', 'emergencyPhone', 'education', 'room', 'coordinator', 'special', 'notes'] },
  medical:      { tab: 'Medical',       cols: ['beneficiaryId', 'beneficiaryName', 'category', 'branchId', 'kind', 'date', 'value', 'notes', 'nextFollowUp'] },
  safeguard:    { tab: 'Safeguarding',  cols: ['beneficiaryId', 'beneficiaryName', 'category', 'branchId', 'kind', 'date', 'notes'] },
  care:         { tab: 'Care',          cols: ['beneficiaryId', 'beneficiaryName', 'category', 'branchId', 'kind', 'date', 'notes', 'nextFollowUp', 'staff'] },
  attendance:   { tab: 'Attendance',    cols: ['date', 'branchId', 'group', 'presentCount', 'absentCount'] },
  person:       { tab: 'Staff',         cols: ['name', 'kind', 'phone', 'designation', 'department', 'branchId', 'joinDate', 'status', 'address', 'emergencyContact', 'responsibilities'] },
  donation:     { tab: 'Donations',     cols: ['date', 'donor', 'donorContact', 'type', 'amount', 'quantity', 'mode', 'purpose', 'restricted', 'receiptNo', 'branchId', 'remarks', 'void', 'voidReason'] },
  expense:      { tab: 'Expenses',      cols: ['date', 'category', 'description', 'amount', 'mode', 'paidTo', 'branchId', 'remarks', 'status', 'enteredBy', 'verifiedBy', 'approvedBy', 'paidBy', 'void', 'voidReason'] },
  leave:        { tab: 'Leave',         cols: ['personName', 'personId', 'leaveType', 'fromDate', 'toDate', 'days', 'reason', 'branchId', 'status', 'enteredBy', 'verifiedBy', 'approvedBy', 'rejectedBy', 'cancelledBy'] },
  item:         { tab: 'Inventory',     cols: ['name', 'category', 'unit', 'minStock', 'expiryDate', 'branchId'] },
  stock:        { tab: 'StockLog',      cols: ['itemId', 'itemName', 'branchId', 'kind', 'qty', 'date', 'note'] },
  announcement: { tab: 'Announcements', cols: ['title', 'body', 'date', 'urgent'] },
  audit:        { tab: 'AuditLog',      cols: ['action', 'entity', 'targetId', 'summary', 'by', 'at'] },
  settings:     { tab: 'Settings',      cols: ['name'] }
};
var META = ['id', 'rev', 'version', 'updatedAt', 'by', 'deleted', 'hash', 'lineage'];   // then the readable columns, then json
var LWW = { audit: 1, settings: 1 };   // types where the newest write simply wins (no conflict dialog)

// Role-based access control (mirror of lib/core/perms.dart). The admin (Super Admin) may do everything. null = every approved user.
var MGR = ['ngo_admin', 'home_manager'];
var COORD = ['children_coordinator', 'oldage_coordinator', 'patient_coordinator'];
var CARE = MGR.concat(COORD, ['caretaker', 'doctor', 'volunteer']);
var MEDICAL = MGR.concat(COORD, ['doctor']);
var SAFE = MGR.concat(COORD);
var MONEYW = MGR.concat(['accountant']);
var MONEYR = MGR.concat(['accountant', 'auditor']);
var STOCKW = MGR.concat(COORD, ['caretaker', 'doctor']);
var STOCKR = STOCKW.concat(['accountant', 'auditor']);
var ATTW = MGR.concat(COORD, ['caretaker']);
var ATTR = ATTW.concat(['auditor']);
var EXPENSEW = MGR.concat(COORD, ['caretaker', 'accountant']);
var BENR = MGR.concat(COORD, ['caretaker', 'doctor', 'volunteer', 'auditor']);
var BENW = MGR.concat(COORD);
var BROAD = ['ngo_admin', 'home_manager', 'doctor', 'auditor', 'caretaker', 'volunteer', 'accountant'];   // see every beneficiary category
var COORD_CAT = { children_coordinator: 'child', oldage_coordinator: 'elder', patient_coordinator: 'patient' };
var ALL_ROLES = ['ngo_admin', 'home_manager', 'children_coordinator', 'oldage_coordinator', 'patient_coordinator', 'doctor', 'accountant', 'caretaker', 'volunteer', 'auditor'];
var READ = { branch: null, beneficiary: BENR, medical: MEDICAL, safeguard: SAFE, care: CARE, attendance: ATTR, person: ['ngo_admin', 'home_manager', 'auditor'], leave: ['ngo_admin', 'home_manager', 'auditor'], donation: MONEYR, expense: MONEYR, item: STOCKR, stock: STOCKR, announcement: null, settings: null, audit: null };
var WRITE = { branch: [], beneficiary: BENW, medical: MEDICAL, safeguard: SAFE, care: CARE, attendance: ATTW, person: MGR, leave: null, donation: MONEYW, expense: EXPENSEW, item: MGR, stock: STOCKW, announcement: MGR, settings: [], audit: null };
// Types that belong to a branch: a person assigned to a branch only receives and writes that branch's records.
var BRANCH_SCOPED = { beneficiary: 1, medical: 1, safeguard: 1, care: 1, attendance: 1, person: 1, leave: 1, donation: 1, expense: 1, item: 1, stock: 1 };
// Expenses and leave requests can be entered by people who may not read the whole list: they receive only the entries they made.
var READ_OWN = { expense: 1, leave: 1 };   // leave: everybody may request leave and sees their own requests

function allowed_(who, table, type) {
  if (who.role === 'admin') return true;
  var need = table[type];
  if (need === null || need === undefined) return need === null;
  for (var i = 0; i < who.roles.length; i++) if (need.indexOf(who.roles[i]) >= 0) return true;
  return false;
}
var USER_HEADER = ['mobile', 'name', 'role', 'status', 'lastSeen', 'createdAt', 'roles', 'branch'];
var DEVICE_HEADER = ['deviceId', 'mobile', 'name', 'status', 'tokenHash', 'issue', 'requestedAt', 'lastSeen'];
var PAGE = 1500;

// ------------------------------------------------------------------ entry points
function doGet() {
  return out_({ ok: true, app: 'Freely NGO', initialised: !!props_().getProperty('ORG_ID') });
}

function doPost(e) {
  var lock = LockService.getScriptLock();
  try {
    lock.waitLock(30000);
    var req = JSON.parse(e.postData.contents);
    var fn = ACTIONS[req.action];
    if (!fn) throw err_('Unknown action', 'BAD');
    return out_(fn(req));
  } catch (ex) {
    return out_({ ok: false, error: String(ex.message || ex), code: ex.code || 'ERR', status: ex.status || '' });
  } finally {
    try { lock.releaseLock(); } catch (x) {}
  }
}

var ACTIONS = {
  init: init_, join: join_, status: status_, recover: recover_,
  sync: sync_, users: users_, approve: approve_, reject: reject_, setUserStatus: setUserStatus_, setRoles: setRoles_, setBranch: setBranch_, forceLogout: forceLogout_
};

// ------------------------------------------------------------------ small helpers
function out_(o) { return ContentService.createTextOutput(JSON.stringify(o)).setMimeType(ContentService.MimeType.JSON); }
function err_(msg, code, status) { var e = new Error(msg); e.code = code || 'ERR'; e.status = status || ''; return e; }
function props_() { return PropertiesService.getScriptProperties(); }
function ss_() { return SpreadsheetApp.getActiveSpreadsheet(); }
function nowIso_() { return new Date().toISOString(); }
function token_() { return Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, ''); }

function sha_(s) {
  var b = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, s, Utilities.Charset.UTF_8);
  return b.map(function (x) { var h = (x < 0 ? x + 256 : x).toString(16); return h.length < 2 ? '0' + h : h; }).join('');
}

function mobile_(s) {
  var d = String(s || '').replace(/\D/g, '');
  if (d.length === 12 && d.indexOf('91') === 0) d = d.substring(2);
  if (d.length === 11 && d.charAt(0) === '0') d = d.substring(1);
  return d;
}

function rolesOf_(cell) {
  var l = String(cell || '').split(',').map(function (x) { return x.trim(); }).filter(function (x) { return ALL_ROLES.indexOf(x) >= 0; });
  return l;
}

function header_(type) { return META.concat(TYPES[type].cols).concat(['json']); }

/** Creates the tab when missing. Whole tab is plain text so that nothing typed by a user is ever treated as a formula. */
function sheet_(name, header) {
  var ss = ss_(), sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.getRange(1, 1, sh.getMaxRows(), Math.max(header.length, 10)).setNumberFormat('@');
    sh.getRange(1, 1, 1, header.length).setValues([header]).setFontWeight('bold');
    sh.setFrozenRows(1);
  }
  return sh;
}

function write_(sh, row, values) {   // values: array of rows, written starting at 'row'
  var r = sh.getRange(row, 1, values.length, values[0].length);
  r.setNumberFormat('@');
  r.setValues(values);
}

function table_(sh, width) {
  var last = sh.getLastRow();
  return last > 1 ? sh.getRange(2, 1, last - 1, width).getValues() : [];
}

function cell_(v) {
  if (v === null || v === undefined) return '';
  if (Object.prototype.toString.call(v) === '[object Array]') return v.join(', ');
  return String(v);
}

function parse_(s, fallback) { try { return JSON.parse(s); } catch (e) { return fallback; } }

// ------------------------------------------------------------------ users and devices
function userRows_() { var sh = sheet_('Users', USER_HEADER); return { sh: sh, rows: table_(sh, USER_HEADER.length) }; }
function deviceRows_() { var sh = sheet_('Devices', DEVICE_HEADER); return { sh: sh, rows: table_(sh, DEVICE_HEADER.length) }; }

function indexOf_(rows, col, val) {
  for (var i = 0; i < rows.length; i++) if (String(rows[i][col]) === String(val)) return i;
  return -1;
}

function setCell_(sh, rowIdx, col, value) {   // rowIdx = index in rows (0 based) -> sheet row rowIdx + 2
  var r = sh.getRange(rowIdx + 2, col + 1);
  r.setNumberFormat('@');
  r.setValue(value);
}

/** Who is calling? Throws a DENIED error (with the reason in .status) when the phone is not allowed. */
function auth_(req, needAdmin) {
  var p = props_().getProperties();
  if (!p.ORG_ID) throw err_('The organization is not set up yet', 'NOSETUP');
  var mobile = mobile_(req.mobile), token = String(req.token || '');
  if (!mobile || !token) throw err_('Not authorised', 'DENIED', 'unknown');
  var h = sha_(token);
  if (h === p.ADMIN_HASH && mobile === p.ADMIN_MOBILE) return { role: 'admin', roles: ALL_ROLES, branch: '', mobile: mobile, deviceId: String(req.deviceId || '') };
  if (needAdmin) throw err_('Admin only', 'DENIED', 'user');
  var devs = deviceRows_(), di = indexOf_(devs.rows, 0, req.deviceId);
  if (di < 0 || String(devs.rows[di][1]) !== mobile) throw err_('Not authorised', 'DENIED', 'unknown');
  var dstatus = String(devs.rows[di][3]);
  if (dstatus !== 'approved') throw err_('This phone is not approved', 'DENIED', dstatus);   // pending / rejected / disabled / loggedout
  if (devs.rows[di][4] !== h) throw err_('Not authorised', 'DENIED', 'unknown');
  var us = userRows_(), ui = indexOf_(us.rows, 0, mobile);
  if (ui < 0 || us.rows[ui][3] !== 'approved') throw err_('Your access was removed', 'DENIED', ui < 0 ? 'unknown' : String(us.rows[ui][3]));
  return { role: String(us.rows[ui][2]), roles: rolesOf_(us.rows[ui][6]), branch: String(us.rows[ui][7] || ''), mobile: mobile, deviceId: String(req.deviceId) };
}

function touch_(who) {
  var now = nowIso_();
  var us = userRows_(), ui = indexOf_(us.rows, 0, who.mobile);
  if (ui >= 0) setCell_(us.sh, ui, 4, now);
  if (who.deviceId) {
    var ds = deviceRows_(), di = indexOf_(ds.rows, 0, who.deviceId);
    if (di >= 0) setCell_(ds.sh, di, 7, now);
  }
}

// ------------------------------------------------------------------ setup / joining
function init_(req) {
  var p = props_();
  if (p.getProperty('ORG_ID')) throw err_('This spreadsheet already has an organization. If you are the admin on a new phone, use "New phone? Enter admin key".', 'ALREADY');
  var name = String(req.orgName || '').trim(), mob = mobile_(req.mobile);
  if (name.length < 2) throw err_('NGO name is required', 'BAD');
  if (mob.length !== 10) throw err_('A 10-digit mobile number is required', 'BAD');
  var code = '';
  var chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  for (var i = 0; i < 8; i++) code += chars.charAt(Math.floor(Math.random() * chars.length));
  var token = token_();
  p.setProperties({
    ORG_ID: Utilities.getUuid(), ORG_NAME: name, ORG_CODE: code, ADMIN_MOBILE: mob, ADMIN_HASH: sha_(token), REV: '0'
  });
  sheet_('Users', USER_HEADER);
  sheet_('Devices', DEVICE_HEADER);
  for (var t in TYPES) sheet_(TYPES[t].tab, header_(t));
  var org = sheet_('Organization', ['key', 'value']);
  write_(org, 2, [['NGO name', name], ['NGO code', code], ['Organization id', p.getProperty('ORG_ID')], ['Admin mobile', mob], ['Created', nowIso_()]]);
  var us = userRows_();
  write_(us.sh, 2, [[mob, String(req.name || '').trim(), 'admin', 'approved', nowIso_(), nowIso_(), ALL_ROLES.join(','), '']]);
  var s1 = ss_().getSheetByName('Sheet1');
  if (s1 && ss_().getSheets().length > 1) ss_().deleteSheet(s1);
  return { ok: true, orgId: p.getProperty('ORG_ID'), orgName: name, orgCode: code, adminToken: token };
}

function checkCode_(req) {
  var p = props_().getProperties();
  if (!p.ORG_ID) throw err_('The organization is not set up yet', 'NOSETUP');
  if (String(req.orgCode || '').trim().toUpperCase() !== p.ORG_CODE) throw err_('Invalid organization code', 'BAD');
  return p;
}

/** A user asks to join with this phone. Always needs the admin's approval (also after a logout). */
function join_(req) {
  var p = checkCode_(req);
  var mob = mobile_(req.mobile), dev = String(req.deviceId || '');
  if (mob.length !== 10 || !dev) throw err_('A 10-digit mobile number is required', 'BAD');
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (mob === p.ADMIN_MOBILE) throw err_('This mobile number belongs to the admin. Choose "I am the admin" and use your admin key.', 'BAD');
  if (ui >= 0 && us.rows[ui][3] === 'disabled') throw err_('Your access was removed by the admin', 'DENIED', 'disabled');
  var name = String(req.name || '').trim();
  if (ui < 0) write_(us.sh, us.rows.length + 2, [[mob, name, 'user', 'pending', '', nowIso_(), '', '']]);
  else if (name) setCell_(us.sh, ui, 1, name);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, dev);
  var row = [dev, mob, name, 'pending', '', '', nowIso_(), ''];
  if (di < 0) write_(ds.sh, ds.rows.length + 2, [row]); else write_(ds.sh, di + 2, [row]);
  return { ok: true, status: 'pending', orgName: p.ORG_NAME, orgId: p.ORG_ID };
}

/** The waiting phone asks whether it was approved. The secret token is handed over exactly once. */
function status_(req) {
  var p = checkCode_(req);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0 || String(ds.rows[di][1]) !== mobile_(req.mobile)) return { ok: true, status: 'unknown', orgName: p.ORG_NAME };
  var st = String(ds.rows[di][3]);
  if (st === 'approved' && ds.rows[di][5] === 'yes') {
    var token = token_();
    setCell_(ds.sh, di, 4, sha_(token));
    setCell_(ds.sh, di, 5, '');
    return { ok: true, status: 'approved', token: token, role: 'user', orgName: p.ORG_NAME, orgId: p.ORG_ID };
  }
  return { ok: true, status: st, orgName: p.ORG_NAME };
}

/** The admin on a new phone proves ownership with the admin key. */
function recover_(req) {
  var who = auth_(req, true);
  var p = props_().getProperties();
  touch_(who);
  return { ok: true, orgId: p.ORG_ID, orgName: p.ORG_NAME, orgCode: p.ORG_CODE, role: 'admin' };
}

// ------------------------------------------------------------------ admin actions
function users_(req) {
  auth_(req, true);
  var us = userRows_(), ds = deviceRows_(), p = props_().getProperties();
  return {
    ok: true, orgCode: p.ORG_CODE,
    users: us.rows.map(function (r) { return { mobile: String(r[0]), name: String(r[1]), role: String(r[2]), status: String(r[3]), lastSeen: String(r[4]), createdAt: String(r[5]), roles: String(r[2]) === 'admin' ? ALL_ROLES : rolesOf_(r[6]), branch: String(r[7] || '') }; }),
    devices: ds.rows.map(function (r) { return { deviceId: String(r[0]), mobile: String(r[1]), name: String(r[2]), status: String(r[3]), requestedAt: String(r[6]), lastSeen: String(r[7]) }; })
  };
}

function approve_(req) {
  auth_(req, true);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0) throw err_('Request not found', 'BAD');
  setCell_(ds.sh, di, 3, 'approved');
  setCell_(ds.sh, di, 5, 'yes');   // the phone collects its token on its next status check
  var us = userRows_(), ui = indexOf_(us.rows, 0, ds.rows[di][1]);
  if (ui >= 0) setCell_(us.sh, ui, 3, 'approved');
  return { ok: true };
}

function reject_(req) {
  auth_(req, true);
  var ds = deviceRows_(), di = indexOf_(ds.rows, 0, req.deviceId);
  if (di < 0) throw err_('Request not found', 'BAD');
  setCell_(ds.sh, di, 3, 'rejected');
  var us = userRows_(), ui = indexOf_(us.rows, 0, ds.rows[di][1]);
  if (ui >= 0 && us.rows[ui][3] === 'pending') setCell_(us.sh, ui, 3, 'rejected');
  return { ok: true };
}

function setUserStatus_(req) {
  auth_(req, true);
  var st = String(req.status);
  if (st !== 'approved' && st !== 'disabled') throw err_('Invalid status', 'BAD');
  var mob = mobile_(req.targetMobile);
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (ui < 0 || us.rows[ui][2] === 'admin') throw err_('User not found', 'BAD');
  setCell_(us.sh, ui, 3, st);
  if (st === 'disabled') {
    var ds = deviceRows_();
    for (var i = 0; i < ds.rows.length; i++) if (String(ds.rows[i][1]) === mob) setCell_(ds.sh, i, 3, 'disabled');
  }
  return { ok: true };
}

/** The admin gives a person one or more NGO roles (home manager, doctor, accountant, ...). Takes effect at that person's next sync. */
function setRoles_(req) {
  auth_(req, true);
  var mob = mobile_(req.targetMobile), roles = rolesOf_((req.roles || []).join(','));
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (ui < 0 || us.rows[ui][2] === 'admin') throw err_('User not found', 'BAD');
  setCell_(us.sh, ui, 6, roles.join(','));
  return { ok: true, roles: roles };
}

/** The admin assigns a person to ONE branch ('' = all branches). From then on that phone only receives and writes that branch's records. */
function setBranch_(req) {
  auth_(req, true);
  var mob = mobile_(req.targetMobile), branch = String(req.branch || '');
  var us = userRows_(), ui = indexOf_(us.rows, 0, mob);
  if (ui < 0 || us.rows[ui][2] === 'admin') throw err_('User not found', 'BAD');
  if (branch && loadTab_('branch').index[branch] === undefined) throw err_('Branch not found', 'BAD');
  setCell_(us.sh, ui, 7, branch);
  return { ok: true, branch: branch };
}

/** Every user phone is logged out: their tokens stop working and they must join and be approved again. */
function forceLogout_(req) {
  auth_(req, true);
  var ds = deviceRows_();
  for (var i = 0; i < ds.rows.length; i++) {
    if (ds.rows[i][3] === 'approved') { setCell_(ds.sh, i, 3, 'loggedout'); setCell_(ds.sh, i, 4, ''); }
  }
  return { ok: true };
}

// ------------------------------------------------------------------ data sync
function loadTab_(type) {
  var width = header_(type).length;
  var sh = sheet_(TYPES[type].tab, header_(type));
  var vals = table_(sh, width);
  var index = {};
  for (var i = 0; i < vals.length; i++) index[String(vals[i][0])] = i;
  return { type: type, sh: sh, width: width, vals: vals, index: index, appended: [] };
}

function wireOf_(type, row) {
  return {
    id: String(row[0]), type: type, rev: Number(row[1]) || 0, version: Number(row[2]) || 1, updatedAt: String(row[3]), by: String(row[4]),
    deleted: String(row[5]) === 'true', hash: String(row[6]), lineage: parse_(row[7], []), data: parse_(row[row.length - 1], {})
  };
}

function rowOf_(type, w, rev) {
  var cols = TYPES[type].cols;
  var row = [w.id, String(rev), String(w.version), String(w.updatedAt), String(w.by || ''), w.deleted ? 'true' : 'false', w.hash, JSON.stringify(w.lineage || [])];
  for (var i = 0; i < cols.length; i++) row.push(cell_(w.data[cols[i]]));
  row.push(JSON.stringify(w.data));
  return row;
}

function has_(list, v) { return list && list.indexOf(v) >= 0; }

function anyRole_(who, list) {
  for (var i = 0; i < who.roles.length; i++) if (list.indexOf(who.roles[i]) >= 0) return true;
  return false;
}

/** Beneficiary categories this person may see, or null for all of them (a coordinator only sees their own category). */
function categoriesOf_(who) {
  if (who.role === 'admin' || anyRole_(who, BROAD)) return null;
  var c = [];
  for (var i = 0; i < who.roles.length; i++) if (COORD_CAT[who.roles[i]]) c.push(COORD_CAT[who.roles[i]]);
  return c.length ? c : null;
}

/** Branch a record belongs to: records about a beneficiary follow the beneficiary (so a transfer takes the history along). */
function branchOf_(tab, data, bmap) {
  if (data && data.beneficiaryId && bmap[data.beneficiaryId] !== undefined) return bmap[data.beneficiaryId];
  return data && data.branchId ? String(data.branchId) : '';
}

function categoryOf_(type, data) {
  if (type === 'beneficiary' || type === 'medical' || type === 'care' || type === 'safeguard') return String(data.category || '');
  if (type === 'attendance') return String(data.group || '');
  return null;   // not category-specific
}

/** May this person see / write a record with this data? Branch assignment and (for coordinators) the beneficiary category. */
function inScope_(who, cats, type, data, bmap) {
  if (BRANCH_SCOPED[type] && who.branch) {
    var b = branchOf_(type, data, bmap);
    if (b !== who.branch) return false;
  }
  if (cats) {
    var cat = categoryOf_(type, data);
    if (cat !== null && cats.indexOf(cat) < 0) return false;
  }
  return true;
}

var EXPENSE_VERIFY = ['ngo_admin', 'home_manager'], EXPENSE_APPROVE = ['ngo_admin'], EXPENSE_PAY = ['accountant'];
function canDo_(who, list) { return who.role === 'admin' || anyRole_(who, list); }

var LEAVE_VERIFY = ['ngo_admin', 'home_manager'], LEAVE_APPROVE = ['ngo_admin'];
/** Leave workflow: requested -> verified (manager) -> approved (administrator); or rejected / cancelled. Nobody may verify or approve
 *  their own request (the Super Admin excepted). Approved / rejected / cancelled requests can no longer be edited.
 *  Returns an error text, or '' when the change is allowed. */
function leaveRule_(who, cur, c) {
  var to = String(c.data.status || 'requested');
  if (!cur) return (to === 'requested' && String(c.data.enteredBy) === who.mobile) ? '' : 'A new leave request must start as requested by you';
  var from = String(cur.data.status || 'requested');
  var own = String(cur.data.enteredBy) === who.mobile && who.role !== 'admin';
  if (to === from) {
    if (from === 'requested') return (own || canDo_(who, LEAVE_VERIFY)) ? '' : 'Not your request';
    var keys = ['fromDate', 'toDate', 'days', 'leaveType', 'personId', 'personName', 'branchId'];
    for (var i = 0; i < keys.length; i++) if (String(cur.data[keys[i]]) !== String(c.data[keys[i]])) return 'This request is already ' + from + ' and cannot be edited';
    return '';
  }
  if (from === 'requested' && to === 'verified') return (!own && canDo_(who, LEAVE_VERIFY)) ? '' : 'Only a manager can verify (not your own request)';
  if (from === 'requested' && to === 'cancelled') return String(cur.data.enteredBy) === who.mobile ? '' : 'Only the person who asked can cancel';
  if ((from === 'requested' || from === 'verified') && to === 'rejected') return (!own && canDo_(who, LEAVE_VERIFY)) ? '' : 'Not allowed';
  if (from === 'verified' && to === 'approved') return (!own && canDo_(who, LEAVE_APPROVE)) ? '' : 'Only the administrator can approve (not your own request)';
  if (from === 'verified' && to === 'cancelled') return String(cur.data.enteredBy) === who.mobile ? '' : 'Only the person who asked can cancel';
  if (from === 'approved' && to === 'cancelled') return canDo_(who, LEAVE_APPROVE) ? '' : 'Only the administrator can cancel approved leave';
  return 'Invalid step';
}

/** Expense workflow: entered -> verified -> approved -> paid (or rejected). Each step needs its own role; approved / paid /
 *  rejected expenses can no longer be edited (only voided). Returns an error text, or '' when the change is allowed. */
function expenseRule_(who, cur, c) {
  var to = String(c.data.status || 'entered');
  if (!cur) return (to === 'entered' && String(c.data.enteredBy) === who.mobile) ? '' : 'A new expense must start as entered by you';
  var from = String(cur.data.status || 'entered');
  if (to === from) {
    if (from === 'entered') return '';
    var keys = ['amount', 'date', 'category', 'description', 'paidTo', 'branchId'];
    for (var i = 0; i < keys.length; i++) if (String(cur.data[keys[i]]) !== String(c.data[keys[i]])) return 'This expense is already ' + from + ' and cannot be edited';
    return '';
  }
  if (from === 'entered' && (to === 'verified' || to === 'rejected')) return canDo_(who, EXPENSE_VERIFY) ? '' : 'Only a manager can verify';
  if (from === 'verified' && to === 'approved') return canDo_(who, EXPENSE_APPROVE) ? '' : 'Only the administrator can approve';
  if (from === 'verified' && to === 'rejected') return canDo_(who, EXPENSE_APPROVE.concat(EXPENSE_VERIFY)) ? '' : 'Not allowed';
  if (from === 'approved' && to === 'paid') return canDo_(who, EXPENSE_PAY) ? '' : 'Only the accountant can record payment';
  if (from === 'approved' && to === 'rejected') return canDo_(who, EXPENSE_APPROVE) ? '' : 'Not allowed';
  return 'Invalid step';
}

function sync_(req) {
  var who = auth_(req, false);
  var admin = who.role === 'admin';
  var p = props_();
  var rev = Number(p.getProperty('REV')) || 0;
  var since = Number(req.since) || 0;
  var tabs = {};
  function tab(t) { return tabs[t] || (tabs[t] = loadTab_(t)); }

  var cats = categoriesOf_(who);
  var bmap = {};      // beneficiary id -> its current branch (records about a beneficiary follow it)
  (function () {
    var bt = tab('beneficiary');
    for (var bi = 0; bi < bt.vals.length; bi++) {
      var bd = parse_(bt.vals[bi][bt.width - 1], {});
      bmap[String(bt.vals[bi][0])] = bd.branchId ? String(bd.branchId) : '';
    }
  })();

  // ---- 1. changes sent by the phone
  var accepted = [], conflicts = [], changes = req.changes || [];
  function write(t, c, existingIdx) {
    rev += 1;
    var row = rowOf_(t.type, c, rev);
    if (existingIdx === undefined) {
      t.index[c.id] = t.vals.length;
      t.vals.push(row);
      t.appended.push(row);
    } else {
      t.vals[existingIdx] = row;
      write_(t.sh, existingIdx + 2, [row]);
    }
    if (t.type === 'beneficiary') bmap[String(c.id)] = c.data.branchId ? String(c.data.branchId) : '';
    if (t.type === 'settings' && c.data && c.data.name) {
      p.setProperty('ORG_NAME', String(c.data.name));
      var org = ss_().getSheetByName('Organization');
      if (org) { var r = org.getRange(2, 2); r.setNumberFormat('@'); r.setValue(String(c.data.name)); }
    }
  }
  for (var k = 0; k < changes.length; k++) {
    var c = changes[k];
    if (!c || !TYPES[c.type] || !c.id || !c.hash || !c.data || typeof c.data !== 'object') continue;
    var t = tab(c.type);
    var ex = t.index[String(c.id)];
    var cur = ex === undefined ? null : wireOf_(c.type, t.vals[ex]);
    if (!allowed_(who, WRITE, c.type)) continue;              // this user's roles may not write this kind of record
    if (c.type === 'audit' && !admin && c.data.by !== who.mobile) continue;
    if ((c.type === 'donation' || c.type === 'expense') && cur && cur.data.void === true && c.data.void !== true) continue;   // a voided entry stays voided
    if (!inScope_(who, cats, c.type, c.data, bmap)) continue;      // outside this person's branch / category
    if (cur && !inScope_(who, cats, c.type, cur.data, bmap)) continue;   // and it must not take over another branch's record
    if (c.type === 'expense' && expenseRule_(who, cur, c)) continue;
    if (c.type === 'leave' && leaveRule_(who, cur, c)) continue;

    if (!cur) {
      write(t, c);
      accepted.push({ id: c.id, hash: c.hash });
    } else if (cur.hash === c.hash) {
      accepted.push({ id: c.id, hash: c.hash });
    } else if (LWW[c.type]) {
      if (Number(c.version) > cur.version || (Number(c.version) === cur.version && String(c.updatedAt) > cur.updatedAt)) write(t, c, ex);
      accepted.push({ id: c.id, hash: c.hash });
    } else if (has_(c.lineage, cur.hash)) {
      write(t, c, ex);                                        // the phone's copy was made from the sheet's copy: take it
      accepted.push({ id: c.id, hash: c.hash });
    } else if (has_(cur.lineage, c.hash)) {
      accepted.push({ id: c.id, hash: c.hash });              // the phone's copy is older than the sheet's: it will get the newer one below
    } else {
      conflicts.push({ id: c.id, server: cur });              // both changed it: nothing is overwritten, the phone asks the user
    }
  }
  for (var tn in tabs) {                                      // new rows in one write per tab
    var tb = tabs[tn];
    if (tb.appended.length) {
      var first = tb.vals.length - tb.appended.length + 2;
      write_(tb.sh, first, tb.appended);
      tb.appended = [];
    }
  }
  p.setProperty('REV', String(rev));
  touch_(who);

  // ---- 2. what changed since the phone's last sync
  var send = [];
  for (var type in TYPES) {
    var readAll = allowed_(who, READ, type);
    if (!readAll && !(READ_OWN[type] && allowed_(who, WRITE, type))) continue;   // never leaves the sheet for phones without the role
    var tt = tab(type);
    for (var r = 0; r < tt.vals.length; r++) {
      if ((Number(tt.vals[r][1]) || 0) <= since) continue;
      var w = wireOf_(type, tt.vals[r]);
      if (type === 'audit' && !admin && w.data.by !== who.mobile) continue;
      if (!readAll && String(w.data.enteredBy) !== who.mobile) continue;      // people who may only enter these see their own entries
      if (!inScope_(who, cats, type, w.data, bmap)) continue;
      send.push(w);
    }
  }
  send.sort(function (x, y) { return x.rev - y.rev; });
  var more = false, newRev = rev;
  if (send.length > PAGE) { send = send.slice(0, PAGE); more = true; newRev = send[send.length - 1].rev; }
  return {
    ok: true, rev: newRev, more: more, records: send, accepted: accepted, conflicts: conflicts,
    orgName: p.getProperty('ORG_NAME'), role: who.role, roles: who.roles, branch: who.branch
  };
}
