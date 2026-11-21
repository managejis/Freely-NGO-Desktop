import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freely_ngo_desktop/core/app_state.dart';
import 'package:freely_ngo_desktop/core/db.dart';
import 'package:freely_ngo_desktop/core/store.dart';
import 'package:freely_ngo_desktop/core/util.dart';
import 'package:freely_ngo_desktop/main.dart';
import 'package:path/path.dart' as p;

/// Real widget tests of the desktop window against a real (temporary) SQLite database, at several window sizes.
Future<void> settle(WidgetTester t, {Finder? until}) async {
  // the database runs in another isolate, so give real time to its answers
  for (var i = 0; i < 40; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 150)));
    await t.pump(const Duration(milliseconds: 100));
    if (until != null && until.evaluate().isNotEmpty) break;
    if (until == null && i >= 5) break;
  }
}

/// Lets in-flight database queries finish so no timer is left pending when the test ends.
Future<void> finish(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.runAsync(() => Future.delayed(const Duration(milliseconds: 400)));
  await t.pump(const Duration(seconds: 11));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    Db.testPath = p.join(Directory.systemTemp.createTempSync('ngo_desktop_test').path, 'test.db');
    final app = AppState.instance;
    await app.load();
    await app.becomeAdmin(mobile: '9876543210', orgRow: {'id': 'org1', 'name': 'Hope Foundation', 'code': 'ABCD2345'}, adminName: 'Admin Test');
    final br = await Store.save(tBranch, data: {'name': 'Sunrise Children Home', 'kind': 'Children Home'});
    await Store.save(tBeneficiary, data: {
      'bid': 'CH-TEST01', 'name': 'Ravi Kumar', 'category': 'child', 'gender': 'Male', 'branchId': br.id, 'status': 'Active',
      'admissionDate': dateStr(today()), 'history': [{'event': 'Admitted', 'date': dateStr(today()), 'branchId': br.id}],
    });
    await Store.save(tPerson, data: {'name': 'Meena', 'kind': 'Staff', 'branchId': br.id, 'status': 'Active'});
  });

  const sizes = {
    'large monitor': Size(1920, 1080),
    'laptop': Size(1366, 768),
    'small laptop': Size(1100, 700),
    'tablet': Size(820, 900),
    'narrow window': Size(600, 800),
    'phone width': Size(420, 760),
  };

  for (final e in sizes.entries) {
    testWidgets('dashboard has no layout overflow on a ${e.key} (${e.value.width.toInt()} x ${e.value.height.toInt()})', (t) async {
      t.view.physicalSize = e.value;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const FreelyApp());
      await settle(t, until: find.text('Overview'));
      expect(t.takeException(), isNull);
      expect(find.text('Quick add'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
      if (e.value.width >= 1100) {
        expect(find.text('Beneficiaries'), findsWidgets);   // full sidebar with labels
        expect(find.text('Dashboard'), findsWidgets);
      } else if (e.value.width >= 720) {
        expect(find.byTooltip('Beneficiaries'), findsOneWidget);   // icon rail
        expect(find.text('ACCOUNT'), findsNothing);
      } else {
        expect(find.byIcon(Icons.menu_rounded), findsOneWidget);   // drawer with a top bar
      }
    });
  }

  testWidgets('sidebar opens pages inside the window and keeps the navigation visible', (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const FreelyApp());
    await settle(t);
    await t.tap(find.text('Beneficiaries').first);
    await settle(t, until: find.text('Ravi Kumar'));
    expect(t.takeException(), isNull);
    expect(find.text('Ravi Kumar'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);   // the sidebar is still there
    await t.tap(find.text('Staff and volunteers'));
    await settle(t, until: find.text('Meena'));
    expect(find.text('Meena'), findsOneWidget);
    await t.tap(find.text('Reports'));
    await settle(t, until: find.text('Beneficiary report'));
    expect(t.takeException(), isNull);
    expect(find.text('Beneficiary report'), findsOneWidget);
  });

  testWidgets('narrow window: the drawer opens and lists the pages', (t) async {
    t.view.physicalSize = const Size(480, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const FreelyApp());
    await settle(t);
    await t.tap(find.byIcon(Icons.menu_rounded));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('Dashboard'), findsOneWidget);
    await t.tap(find.text('Donations'));
    await settle(t);
    expect(t.takeException(), isNull);
    expect(find.text('Donations'), findsWidgets);
  });

  testWidgets('a huge window: forms stay narrow and readable', (t) async {
    t.view.physicalSize = const Size(2400, 1300);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const FreelyApp());
    await settle(t);
    await t.tap(find.text('Beneficiaries').first);
    await settle(t, until: find.byTooltip('Register'));
    await t.tap(find.byTooltip('Register'));
    await settle(t, until: find.text('Child'));
    await t.pump(const Duration(seconds: 1));   // let the sheet finish sliding up
    await t.tap(find.text('Child'));
    await settle(t, until: find.text('Full name *'));
    expect(t.takeException(), isNull);
    final w = t.getSize(find.byType(TextFormField).first).width;
    expect(w, lessThanOrEqualTo(760), reason: 'a form field should not stretch across a 2400 px window');
    await finish(t);
  });

  testWidgets('a narrow window: the quick-add sheet and a form fit without overflow', (t) async {
    t.view.physicalSize = const Size(420, 700);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(const FreelyApp());
    await settle(t, until: find.text('Quick add'));
    await t.tap(find.text('Quick add'));
    await settle(t);
    await t.pump(const Duration(seconds: 1));
    expect(t.takeException(), isNull);
    await t.tap(find.text('Register child'));
    await settle(t, until: find.text('Full name *'));
    expect(t.takeException(), isNull);
    expect(find.text('Full name *'), findsOneWidget);
    await finish(t);
  });
}
