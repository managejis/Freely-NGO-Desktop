import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/sync.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

// ====================================================================== profile
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    return SkyScaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Center(child: CircleAvatar(radius: 38, child: Text(app.userName.isEmpty ? '?' : app.userName[0].toUpperCase(), style: const TextStyle(fontSize: 30)))),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Name'),
            subtitle: Text(app.userName),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () async {
              final n = await askText(context, 'Your name', initial: (app.session?['name'] ?? '') as String);
              if (n != null && n.trim().isNotEmpty) await app.setName(n);
            },
          ),
          ListTile(leading: const Icon(Icons.phone_android), title: const Text('Mobile number'), subtitle: Text(app.mobile)),
          ListTile(
            leading: const Icon(Icons.verified_user_outlined),
            title: const Text('Roles'),
            subtitle: Text(app.isAdmin ? 'Super Admin (full access)' : Perms.rolesText(app.roles)),
          ),
          ListTile(leading: const Icon(Icons.volunteer_activism_outlined), title: const Text('NGO'), subtitle: Text(app.orgName)),
          if (app.orgCode.isNotEmpty && app.isAdmin) ListTile(leading: const Icon(Icons.vpn_key_outlined), title: const Text('NGO code'), subtitle: Text(app.orgCode)),
          ListTile(leading: const Icon(Icons.sync), title: const Text('Last sync with the spreadsheet'), subtitle: Text(fmtDateTime(SyncEngine.instance.lastSync))),
          ListTile(leading: const Icon(Icons.smartphone), title: const Text('This device'), subtitle: Text(app.deviceId.length >= 8 ? app.deviceId.substring(0, 8) : app.deviceId)),
        ]),
      ),
    );
  }
}

// ====================================================================== audit log
class AuditScreen extends StatelessWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Audit log')),
      body: Live<List<Rec>>(
        load: Store.audits,
        builder: (c, list) => list.isEmpty
            ? const EmptyState(Icons.history, 'Nothing recorded yet.')
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (c, i) {
                  final a = list[i];
                  final action = a.s('action');
                  return ListTile(
                    dense: true,
                    leading: Icon(action == 'created' ? Icons.add_circle_outline : action == 'deleted' ? Icons.delete_outline : Icons.edit_outlined),
                    title: Text('${a.s('entity')} $action'),
                    subtitle: Text('${a.s('summary')}\nby ${a.s('by')} · ${fmtDateTime(a.s('at'))}'),
                    isThreeLine: true,
                  );
                },
              ),
      ),
    );
  }
}

// ====================================================================== privacy & security
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const items = [
      ('Where your data is', 'Every phone keeps its own copy of the records it is allowed to see. The NGO\'s central copy is a Google Sheet in the admin\'s Google account. Nothing is stored on any other server.'),
      ('Role-based access', 'Each person has one or more roles (home manager, coordinator, doctor, accountant, caretaker, volunteer, auditor ...) and may be assigned to one branch. The spreadsheet only sends a phone the records its roles and branch allow: medical records only reach doctors, coordinators and managers, safeguarding records only managers and coordinators, donations and expenses only the finance roles, and a coordinator sees only their own category (children, residents or patients).'),
      ('Readable spreadsheet', 'The sheet shows beneficiaries, medical records, finance and the audit log as plain text, so anyone who can open that sheet can read them. The admin must keep the sheet private and never share it. Opening the medical or safeguarding information of a beneficiary on a phone is recorded in the audit log.'),
      ('NGOs are isolated', 'Each NGO has its own spreadsheet and its own web app link. Nobody can reach another NGO\'s data.'),
      ('Approval and access', 'A person enters a mobile number and the invite code from the admin and must be approved once by the admin. The admin can disable a person or log every phone out.'),
      ('Finance corrections', 'Donations and expenses are never deleted. A wrong entry is voided with a reason; it stays visible, struck through, and every change is in the audit log. Expenses follow a fixed workflow: entered, verified by a manager, approved by the administrator and paid by the accountant.'),
      ('Secrets', 'Each approved phone holds its own secret key; the sheet stores only a hash of it. Keep the admin key safe: whoever has it can act as the admin.'),
      ('Backups', 'Backup files are encrypted with your password and contain text only. Keep the password safe - it cannot be recovered.'),
      ('Good practice', 'Use a screen lock on the phone and log out on shared phones (logging out removes the NGO\'s records from that phone).'),
    ];
    return SkyScaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final i in items) ...[
          Text(i.$1, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(height: 4),
          Text(i.$2),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }
}

// ====================================================================== help & support
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const faq = [
      ('How do I log in?', 'There is no password. Enter your mobile number and name, paste the invite code your NGO admin gave you, tap Request access and wait for the admin to approve. This happens only once; afterwards the app opens straight in.'),
      ('Why can I not see Medical or Finance?', 'What you see depends on the roles and branch the admin gave you. Ask the admin to change them if you need more access. A person can hold several roles.'),
      ('How do I take attendance?', 'Dashboard > Attendance (or the + button) > choose the group (children, residents, staff or volunteers), the branch and the date, set each person\'s status and save. Attendance appears under Reports.'),
      ('How does an expense get paid?', 'Staff enter the expense. A manager verifies it, the administrator approves it and the accountant records the payment. Only then does it count as paid in the reports.'),
      ('How do I correct a wrong amount?', 'Open the donation or expense and choose Void, with a reason, then enter the correct one. Entries are never deleted.'),
      ('Can I export reports?', 'Yes. Reports > choose a report and a date range > Excel or PDF. The file opens the share sheet (Drive, WhatsApp, e-mail).'),
      ('Does the app work without internet?', 'Yes. Everything is saved on the phone first and copied to the spreadsheet when the internet is on.'),
      ('What is a conflict?', 'Two people changed the same record while their phones were apart. Nothing is overwritten - open Synchronization status and choose which version to keep.'),
      ('How do I back up?', 'Menu > Backup / Restore > Create backup now. Choose a password, then save or share the file somewhere safe. You are also offered a backup every time you log out.'),
      ('I lost my phone (admin)', 'On the new phone choose "I am the admin", enter your mobile number and name, and use "New phone? Enter admin key". The admin key is in Settings on your old phone and in your notes.'),
    ];
    return SkyScaffold(
      appBar: AppBar(title: const Text('Help & Support')),
      body: ListView(children: [
        for (final f in faq) ExpansionTile(title: Text(f.$1), childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12), expandedCrossAxisAlignment: CrossAxisAlignment.start, children: [Text(f.$2)]),
        const SectionTitle('Contact support'),
        ListTile(leading: const Icon(Icons.mail_outline), title: const Text('info@manageji.com'), onTap: () => launchUrl(Uri.parse('mailto:info@manageji.com?subject=Freely%20NGO%20support'))),
        ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('+91 866 744 64 68'), onTap: () => launchUrl(Uri.parse('tel:+918667446468'))),
        const ListTile(leading: Icon(Icons.schedule), title: Text('Monday - Friday, 9:00 AM - 5:00 PM')),
      ]),
    );
  }
}

// ====================================================================== about
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SkyScaffold(
      appBar: AppBar(title: const Text('About App')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Icon(Icons.volunteer_activism, size: 64, color: cs.primary)),
        Center(child: Text(AppConfig.appName, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
        Center(child: Text('NGO Management System · version ${AppConfig.version}', style: TextStyle(color: cs.outline))),
        const SizedBox(height: 12),
        const Text('Freely NGO manages your NGO on your own phones: children, residents, patients, staff and volunteers, attendance, donations, expenses and inventory. '
            'It works offline and shares changes between your NGO\'s devices when the internet is on.', textAlign: TextAlign.center),
        ListTile(leading: const Icon(Icons.public), title: const Text('manageji.com'), subtitle: const Text('Visit our website'), onTap: () => _open('https://manageji.com/')),
        ListTile(leading: const Icon(Icons.mail_outline), title: const Text('info@manageji.com'), onTap: () => _open('mailto:info@manageji.com')),
        ListTile(leading: const Icon(Icons.phone_outlined), title: const Text('+91 866 744 64 68'), onTap: () => _open('tel:+918667446468')),
        const SizedBox(height: 12),
        Center(child: Text('© ManageJi. All rights reserved.', style: TextStyle(color: cs.outline, fontSize: 12))),
      ]),
    );
  }
}
