import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freely_ngo_desktop/core/backup.dart';
import 'package:freely_ngo_desktop/core/cloud.dart';
import 'package:freely_ngo_desktop/core/db.dart';
import 'package:freely_ngo_desktop/core/export.dart';
import 'package:freely_ngo_desktop/core/reports.dart';
import 'package:freely_ngo_desktop/core/store.dart';
import 'package:freely_ngo_desktop/core/util.dart';

Rec stock(String item, num qty) => Rec(id: newId(), orgId: 'o', type: tStock, updatedAt: nowIso(), data: {'itemId': item, 'qty': qty});

void main() {
  test('backup: encrypt/decrypt round trip, wrong password and tampering are rejected', () {
    const plain = '{"format":"freely-backup","entities":[]}';
    final file = Backup.encrypt(plain, 'secret1');
    expect(Backup.decrypt(file, 'secret1')['format'], 'freely-backup');
    expect(() => Backup.decrypt(file, 'wrong'), throwsA(isA<BackupError>()));
    expect(() => Backup.decrypt('not a backup', 'secret1'), throwsA(isA<BackupError>()));
  });

  test('lineage: an edit descends from the previous state', () {
    final r = Rec(id: 'a', orgId: 'o', type: tBeneficiary, data: {'name': 'x'}, updatedAt: '2026-01-01T00:00:00Z');
    final first = r.hash;
    r.edit(by: 'me', newData: {'name': 'y'});
    expect(r.lineage, contains(first));
    expect(r.hash, isNot(first));
    expect(r.version, 2);
  });

  test('invite code and admin key round-trip', () {
    const url = 'https://script.google.com/macros/s/AKfycbxABC-def_123/exec';
    final inv = Sheets.invite('K7M2QX9A', url);
    expect(inv, 'K7M2QX9A.AKfycbxABC-def_123');
    final p = Sheets.parseInvite(inv)!;
    expect(p.code, 'K7M2QX9A');
    expect(p.url, url);
    expect(Sheets.parseInvite('nonsense'), isNull);
  });

  test('mobile numbers are normalised', () {
    expect(normMobile('+91 98765 43210'), '9876543210');
    expect(validMobile('12345'), isFalse);
  });

  test('money uses Indian digit grouping and rounding never drifts', () {
    expect(money(1234567.5), '12,34,567.50');
    expect(money(-950), '-950.00');
    var t = 0.0;
    for (var i = 0; i < 100; i++) {
      t = r2(t + 0.1);
    }
    expect(t, 10.0);
  });

  test('age is computed from the date of birth', () {
    final n = today();
    expect(ageOf(dateStr(DateTime(n.year - 10, n.month, n.day))), 10);
    expect(ageOf(''), isNull);
  });

  test('inventory balance is the sum of stock transactions', () {
    final b = Store.balances([stock('a', 10), stock('a', -3.5), stock('b', 4), stock('a', 1)]);
    expect(b['a'], 7.5);
    expect(b['b'], 4);
  });

  test('beneficiary ids carry the category prefix and are unique', () {
    final a = Store.newBeneficiaryId(catChild), b = Store.newBeneficiaryId(catChild);
    expect(a, startsWith('CH-'));
    expect(Store.newBeneficiaryId(catElder), startsWith('OA-'));
    expect(Store.newBeneficiaryId(catPatient), startsWith('PT-'));
    expect(a, isNot(b));
  });

  test('reports are defined once each, and the entity types cover the backend', () {
    expect(allReports.length, 14);
    expect({for (final r in allReports) r.key}.length, 14);
    expect(entityTypes, containsAll([tBranch, tBeneficiary, tMedical, tSafeguard, tCare, tAttendance, tPerson, tDonation, tExpense, tItem, tStock]));
  });

  test('report export builds a readable Excel file', () {
    final t = ReportTable('Test report', ['A', 'B'], [['1', 'x'], ['2', 'y']], footer: ['Total: 2']);
    final x = Excel.decodeBytes(Exporter.excelBytes(t, 'All branches'));
    expect(x.tables.keys.first, 'Test report');
    expect(x.tables.values.first.maxRows, greaterThanOrEqualTo(7));
  });

  test('leave: days are inclusive, balance counts approved days of the financial year', () {
    expect(Store.leaveDays('2026-05-04', '2026-05-06'), 3);
    expect(Store.leaveDays('2026-05-06', '2026-05-04'), 0);
    expect(Store.fyOf(DateTime(2026, 3, 31)), 2025);
    expect(Store.fyOf(DateTime(2026, 4, 1)), 2026);
    Rec l(String type, String from, int days, String status) => Rec(id: newId(), orgId: 'o', type: tLeave, updatedAt: nowIso(), data: {'leaveType': type, 'fromDate': from, 'days': days, 'status': status});
    final list = [l('Casual leave', '2026-05-04', 3, 'approved'), l('Casual leave', '2026-06-01', 2, 'requested'), l('Casual leave', '2027-04-02', 5, 'approved'), l('Sick leave', '2026-07-01', 4, 'approved')];
    expect(Store.usedLeave(list, 'Casual leave', 2026), 3);
    expect(Store.usedLeave(list, 'Sick leave', 2026), 4);
    expect(Store.usedLeave(list, 'Casual leave', 2027), 5);
  });
}
