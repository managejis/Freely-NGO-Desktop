
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/desk.dart';

import '../core/app_state.dart';
import '../core/cloud.dart';
import '../core/db.dart';
import '../core/store.dart';
import '../ui.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get app => AppState.instance;

  Future<void> _rename() async {
    final n = await askText(context, 'NGO name', initial: app.orgName);
    if (n == null || n.trim().length < 2) return;
    await Store.saveSettings(name: n.trim());
  }

  Future<void> _logo() async {
    try {
      final b64 = await Desk.pickLogoBase64();
      if (b64 == null) return;
      await Store.saveSettings(logo: b64);
      if (mounted) toast(context, 'Logo updated');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  Future<void> _autoBackup(bool on) async {
    if (on) {
      final pw = await askText(context, 'Password for automatic backups', hint: 'Remember it - needed to restore', obscure: true);
      if (pw == null || pw.length < 6) {
        if (mounted && pw != null) toast(context, 'Use at least 6 characters');
        return;
      }
      await Db.instance.setKv('auto_backup_pw', pw);
    }
    await app.setAutoBackup(on);
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(children: [
          const SectionTitle('Appearance'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('Theme'),
            trailing: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Auto')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (v) => app.setTheme(v.first),
            ),
          ),
          const ListTile(leading: Icon(Icons.language), title: Text('Language'), subtitle: Text('English. Kannada, Tamil, Telugu and Hindi are planned.')),
          const SectionTitle('Backup'),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('Automatic daily backup'),
            subtitle: const Text('Encrypted backup file kept on this phone (last 7)'),
            value: app.autoBackup,
            onChanged: _autoBackup,
          ),
          if (app.isAdmin) ...[
            const SectionTitle('NGO (admin)'),
            ListTile(leading: const OrgAvatar(size: 36), title: Text(app.orgName), subtitle: const Text('Tap to rename'), onTap: _rename),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('NGO logo'),
              subtitle: const Text('Upload or change'),
              trailing: app.logo == null ? null : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Store.saveSettings(clearLogo: true)),
              onTap: _logo,
            ),
            if (!app.isLocal) ...[
              ListTile(
                leading: const Icon(Icons.vpn_key_outlined),
                title: const Text('Invite code for NGO members'),
                subtitle: Text(Sheets.invite(app.orgCode, app.sheetUrl), maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.copy),
                onTap: () { Clipboard.setData(ClipboardData(text: Sheets.invite(app.orgCode, app.sheetUrl))); toast(context, 'Invite copied'); },
              ),
              ListTile(
                leading: const Icon(Icons.key_outlined),
                title: const Text('Admin key (keep secret)'),
                subtitle: const Text('Needed to recover the NGO on a new phone. Tap to copy and save it safely.'),
                trailing: const Icon(Icons.copy),
                onTap: () { Clipboard.setData(ClipboardData(text: Sheets.adminKey(app.token, app.sheetUrl))); toast(context, 'Admin key copied - store it somewhere safe'); },
              ),
            ],
          ],
        ]),
      ),
    );
  }
}
