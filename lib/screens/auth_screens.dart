import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../core/app_state.dart';
import '../core/cloud.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'backup_screen.dart';

/// Logout. First the user is asked to take a backup, because logging out removes this organization's records from this phone.
Future<void> logoutFlow(BuildContext _) async {
  final ctx = navKey.currentContext;
  if (ctx == null) return;
  final app = AppState.instance;
  final pending = SyncEngine.instance.pending.value;
  final body = StringBuffer('Logging out removes all NGO records (beneficiaries, attendance, donations, expenses, inventory) from this phone')
    ..write(app.isLocal ? ' and, in local mode, they exist nowhere else - they would be LOST.' : '. They stay in the spreadsheet.')
    ..write(pending > 0 ? '\n\n$pending change${pending == 1 ? ' is' : 's are'} not yet in the spreadsheet and would be lost.' : '')
    ..write('\n\nTake a backup now and keep the file somewhere safe (Google Drive, e-mail, WhatsApp). You need its password to restore it.');
  final choice = await showDialog<String>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Take a backup before you log out'),
      content: Text(body.toString()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        OutlinedButton(onPressed: () => Navigator.pop(c, 'skip'), child: const Text('Log out without backup')),
        FilledButton(onPressed: () => Navigator.pop(c, 'backup'), child: const Text('Back up now')),
      ],
    ),
  );
  if (choice == null) return;
  if (choice == 'backup') {
    final c2 = navKey.currentContext;
    if (c2 == null || !await backupNowFlow(c2)) return;     // stay logged in when the backup was not made
    final c3 = navKey.currentContext;
    if (c3 == null || !await confirm(c3, 'Log out now?', 'Your backup was created. Log out and remove the records from this phone?', yes: 'Log out')) return;
  }
  await SyncEngine.instance.stop();
  await app.logout();
  navKey.currentState?.popUntil((r) => r.isFirst);
}

// ====================================================================== first launch: user (default) or admin
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});
  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _mobile = TextEditingController(), _name = TextEditingController();
  final _invite = TextEditingController(), _org = TextEditingController();
  final _url = TextEditingController(), _adminKey = TextEditingController();
  bool _admin = false;      // normal user is the default
  bool _busy = false;
  bool _recover = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, Sheets.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _common() {
    if (!validMobile(_mobile.text)) {
      toast(context, 'Enter your 10-digit mobile number');
      return false;
    }
    if (_name.text.trim().isEmpty) {
      toast(context, 'Enter your name');
      return false;
    }
    return true;
  }

  Future<void> _joinAsUser() async {
    if (!_common()) return;
    final inv = Sheets.parseInvite(_invite.text);
    if (inv == null) return toast(context, 'Paste the invite code your admin gave you');
    await _run(() async {
      final app = AppState.instance;
      final r = await Sheets.call(inv.url, {'action': 'join', 'orgCode': inv.code, 'mobile': normMobile(_mobile.text), 'name': _name.text.trim(), 'deviceId': app.deviceId});
      await app.requestedJoin(normMobile(_mobile.text), {'id': r['orgId'], 'name': r['orgName'], 'code': inv.code}, _name.text, inv.url);
    });
  }

  Future<void> _createOrg() async {
    if (!_common()) return;
    if (_org.text.trim().length < 2) return toast(context, 'Enter the NGO name');
    final url = _url.text.trim();
    if (url.isNotEmpty && !Sheets.validUrl(url)) return toast(context, 'The web app URL must look like https://script.google.com/macros/s/.../exec');
    await _run(() async {
      final app = AppState.instance;
      final mobile = normMobile(_mobile.text);
      if (url.isEmpty) {
        await app.becomeAdmin(mobile: mobile, orgRow: {'id': newId(), 'name': _org.text.trim(), 'code': randomCode(8)}, adminName: _name.text);
      } else {
        final r = await Sheets.call(url, {'action': 'init', 'orgName': _org.text.trim(), 'mobile': mobile, 'name': _name.text.trim()});
        await app.becomeAdmin(
          mobile: mobile, orgRow: {'id': r['orgId'], 'name': r['orgName'], 'code': r['orgCode']}, adminName: _name.text, url: url, adminToken: r['adminToken'] as String);
      }
      await Store.saveSettings();
    });
  }

  /// The admin has a new phone: the admin key proves ownership; all records come back from the spreadsheet.
  Future<void> _recoverAdmin() async {
    if (!_common()) return;
    final k = Sheets.parseAdminKey(_adminKey.text);
    if (k == null) return toast(context, 'Paste your admin key');
    await _run(() async {
      final mobile = normMobile(_mobile.text);
      final r = await Sheets.call(k.url, {'action': 'recover', 'mobile': mobile, 'deviceId': AppState.instance.deviceId, 'token': k.token});
      await AppState.instance.becomeAdmin(
        mobile: mobile, orgRow: {'id': r['orgId'], 'name': r['orgName'], 'code': r['orgCode']}, adminName: _name.text, url: k.url, adminToken: k.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const spinner = SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
    return SkyScaffold(
      maxWidth: 560,
      header: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
          child: Row(children: [
            ClipRRect(borderRadius: BorderRadius.circular(22), child: Image.asset('assets/logo.png', width: 92, height: 92)),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(AppConfig.appName, style: serif(38, color: Colors.white)),
              const Text('NGO Management System', style: TextStyle(color: Colors.white70, fontSize: 13)),
            ])),
          ]),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(_admin ? 'Set up your NGO' : 'Welcome', style: serif(28)),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: false, icon: Icon(Icons.person_outline), label: Text('I am a user')),
                    ButtonSegment(value: true, icon: Icon(Icons.admin_panel_settings_outlined), label: Text('I am the admin')),
                  ],
                  selected: {_admin},
                  onSelectionChanged: (v) => setState(() => _admin = v.first),
                ),
                const SizedBox(height: 8),
                Text(_admin ? 'First time? Set up your NGO and become its admin.' : 'Ask your admin for the invite code. The admin approves you once, then you are in for good.',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.outline, fontSize: 12.5)),
                const SizedBox(height: 16),
                TextField(controller: _mobile, keyboardType: TextInputType.phone, maxLength: 14, decoration: const InputDecoration(labelText: 'Mobile number', prefixIcon: Icon(Icons.phone_android), counterText: '')),
                const SizedBox(height: 12),
                TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(Icons.badge_outlined))),
                const SizedBox(height: 12),
                if (!_admin) ...[
                  TextField(controller: _invite, decoration: const InputDecoration(labelText: 'Invite code', prefixIcon: Icon(Icons.vpn_key_outlined))),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _joinAsUser, child: _busy ? spinner : const Text('Request access')),
                ] else if (!_recover) ...[
                  TextField(controller: _org, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'NGO name', prefixIcon: Icon(Icons.business_outlined))),
                  const SizedBox(height: 12),
                  TextField(controller: _url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Google Sheet web app URL', hintText: 'https://script.google.com/macros/s/.../exec', prefixIcon: Icon(Icons.table_chart_outlined))),
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetupGuideScreen())), icon: const Icon(Icons.menu_book_outlined), label: const Text('How do I get this URL? (setup guide)'))),
                  Text('Leave the URL empty to use this phone only (local mode, no spreadsheet and no other users).', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _createOrg, child: _busy ? spinner : const Text('Create NGO')),
                  TextButton(onPressed: _busy ? null : () => setState(() => _recover = true), child: const Text('New phone? Enter admin key')),
                ] else ...[
                  TextField(controller: _adminKey, decoration: const InputDecoration(labelText: 'Admin key', prefixIcon: Icon(Icons.key_outlined))),
                  const SizedBox(height: 6),
                  Text('Find it in Settings > Organization on your old phone. Your records come back from the spreadsheet.', style: TextStyle(color: cs.outline, fontSize: 12.5)),
                  const SizedBox(height: 16),
                  FilledButton(onPressed: _busy ? null : _recoverAdmin, child: _busy ? spinner : const Text('Recover NGO')),
                  TextButton(onPressed: _busy ? null : () => setState(() => _recover = false), child: const Text('Back')),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ====================================================================== one-time setup of the spreadsheet (admin)
class SetupGuideScreen extends StatelessWidget {
  const SetupGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const steps = [
      'Open Google Sheets with the Google account that should own the data and create a new blank spreadsheet (button below).',
      'In the spreadsheet choose Extensions > Apps Script.',
      'Delete the sample code, then paste the script (tap "Copy script" below) and press Save.',
      'Press Deploy > New deployment. Click the gear and choose "Web app".',
      'Set "Execute as" to Me and "Who has access" to Anyone. Press Deploy.',
      'Google asks you to approve permissions - this is the one-time admin approval. Choose your account, Advanced, "Go to ... (unsafe)", Allow.',
      'Copy the Web app URL (it ends with /exec), paste it into Freely NGO and tap Create NGO.',
    ];
    return SkyScaffold(
      maxWidth: 560,
      appBar: AppBar(title: const Text('Spreadsheet setup guide')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('All your data is kept in a Google Sheet that belongs to you. This is done once.'),
        const SizedBox(height: 12),
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(radius: 13, child: Text('${i + 1}', style: const TextStyle(fontSize: 13))),
              const SizedBox(width: 12),
              Expanded(child: Text(steps[i])),
            ]),
          ),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: () => launchUrl(Uri.parse('https://sheets.new'), mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new), label: const Text('Open Google Sheets (new spreadsheet)')),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () async {
            final s = await rootBundle.loadString('assets/freely_ngo_apps_script.txt');
            await Clipboard.setData(ClipboardData(text: s));
            if (context.mounted) toast(context, 'Script copied. Paste it into the Apps Script editor.');
          },
          icon: const Icon(Icons.copy),
          label: const Text('Copy script'),
        ),
        const SizedBox(height: 16),
        const Text('Afterwards, open the spreadsheet any time to see Users, Devices, Branches, Beneficiaries, Medical, Attendance, Donations, Expenses, Inventory and AuditLog as tabs. '
            'Change data in the app, not in the sheet.', style: TextStyle(fontSize: 13)),
      ]),
    );
  }
}

// ====================================================================== waiting for approval
class PendingScreen extends StatelessWidget {
  const PendingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return SkyScaffold(
      maxWidth: 560,
      appBar: AppBar(title: const Text('Waiting for approval'), actions: [IconButton(tooltip: 'Log out', onPressed: () => logoutFlow(context), icon: const Icon(Icons.logout))]),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Icon(Icons.hourglass_top, size: 64),
          const SizedBox(height: 16),
          Text('Your request to join "${app.orgName}" was sent.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          const Text('The admin has to approve this phone in the app (Users screen). Keep this screen open or come back later - you will be taken in automatically, '
              'and you will not need to do this again.', textAlign: TextAlign.center),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: () { SyncEngine.instance.pollApproval(); toast(context, 'Checking with the admin...'); }, icon: const Icon(Icons.refresh), label: const Text('Check now')),
        ]),
      ),
    );
  }
}

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});
  @override
  Widget build(BuildContext context) => SkyScaffold(
        maxWidth: 560,
        appBar: AppBar(title: const Text('Access removed')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Icon(Icons.block, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('The admin of "${AppState.instance.orgName}" has not approved, or has removed, your access.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('The organization\'s records were removed from this phone. Contact your admin.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(onPressed: () => logoutFlow(context), child: const Text('Log out')),
          ]),
        ),
      );
}
