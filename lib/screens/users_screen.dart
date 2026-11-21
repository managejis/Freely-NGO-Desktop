import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/desk.dart';

import '../core/app_state.dart';
import '../core/cloud.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/users.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

/// Admin only: approve new phones, see last login and status, disable users, log everybody out.
class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  Map<String, dynamic>? _data;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Users.cached().then((c) {
      if (mounted) setState(() => _data = c);
    });
    _refresh();
  }

  Future<void> _refresh() async {
    if (AppState.instance.isLocal) return;
    setState(() { _loading = true; _error = null; });
    try {
      final d = await Users.refresh();
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = Sheets.explain(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _do(Future<void> Function() f, String done) async {
    try {
      await f();
      if (mounted) {
        setState(() => _data = null);
        _data = await Users.cached();
        setState(() {});
        toast(context, done);
      }
    } catch (e) {
      if (mounted) toast(context, Sheets.explain(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final d = _data;
    final users = ((d?['users'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final devices = ((d?['devices'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final reqs = devices.where((x) => x['status'] == 'pending').toList();
    final invite = app.isLocal ? '' : Sheets.invite(app.orgCode, app.sheetUrl);
    return SkyScaffold(
      appBar: AppBar(title: const Text('Users'), actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _loading ? null : _refresh)]),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text('Could not refresh: $_error', style: const TextStyle(color: Colors.red))),
          if (app.isLocal)
            const Padding(padding: EdgeInsets.all(16), child: Text('Local mode: there is no spreadsheet, so other users cannot join. Create the NGO with a Google Sheet web app URL to add users.'))
          else
            Card(
              margin: const EdgeInsets.all(12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Invite code', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  SelectableText(invite, style: const TextStyle(fontSize: 13, fontFamily: 'monospace')),
                  const SizedBox(height: 4),
                  Row(children: [
                    TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: invite)); toast(context, 'Invite copied'); }, icon: const Icon(Icons.copy), label: const Text('Copy')),
                    TextButton.icon(onPressed: () => Desk.copyText(context, 'Join "${app.orgName}" on Freely NGO. In the app choose "I am a user" and paste this invite code:\n$invite'), icon: const Icon(Icons.send_outlined), label: const Text('Copy message')),
                  ]),
                  const Text('Give this to your NGO members. They enter it with their mobile number, and you approve them below. Tap an approved person to set their roles (home manager, doctor, accountant, ...) and their branch.', style: TextStyle(fontSize: 12.5)),
                ]),
              ),
            ),
          SectionTitle('Pending approvals (${reqs.length})'),
          if (reqs.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4), child: Text('No requests right now.')),
          for (final r in reqs)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${r['name']}'.isEmpty ? '${r['mobile']}' : '${r['name']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${r['mobile']} · requested ${fmtDateTime(r['requestedAt'] as String?)}'),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton.icon(icon: const Icon(Icons.check), label: const Text('Approve'), onPressed: () => _do(() => Users.approve(r['deviceId'] as String), '${r['mobile']} approved')),
                    const SizedBox(width: 10),
                    OutlinedButton(onPressed: () => _do(() => Users.reject(r['deviceId'] as String), 'Rejected'), child: const Text('Reject')),
                  ]),
                ]),
              ),
            ),
          SectionTitle('People (${users.length})'),
          for (final m in users)
            ListTile(
              leading: CircleAvatar(child: Icon(m['role'] == 'admin' ? Icons.admin_panel_settings : Icons.person)),
              title: Text('${m['name']}'.isEmpty ? '${m['mobile']}' : '${m['name']}'),
              subtitle: Text('${m['mobile']}\n${m['role'] == 'admin' ? 'Admin' : Perms.rolesText([for (final r in (m['roles'] as List? ?? const [])) '$r'])} · ${_statusText('${m['status']}')} · last seen ${fmtDateTime(m['lastSeen'] as String?)}${'${m['branch'] ?? ''}'.isEmpty ? '' : '\nBranch: ${Store.branchName('${m['branch']}')}'}'),
              isThreeLine: true,
              onTap: m['role'] != 'admin' && m['status'] == 'approved' ? () => _editRoles(m) : null,
              trailing: m['role'] == 'admin'
                  ? null
                  : m['status'] == 'approved'
                      ? TextButton(
                          onPressed: () async {
                            if (!await confirm(context, 'Disable ${m['mobile']}?', 'This account loses access. Their phone removes the organization\'s records the next time it syncs.', yes: 'Disable')) return;
                            await _do(() => Users.setStatus('${m['mobile']}', 'disabled'), 'Disabled');
                          },
                          child: const Text('Disable'))
                      : m['status'] == 'disabled'
                          ? TextButton(onPressed: () => _do(() => Users.setStatus('${m['mobile']}', 'approved'), 'Enabled'), child: const Text('Enable'))
                          : null,
            ),
          if (!app.isLocal) ...[
            const SectionTitle('Security'),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log out all users\' phones'),
              subtitle: const Text('Every user phone stops working at its next sync and removes the records. They must request access and be approved again. Your phone is not affected.'),
              onTap: () async {
                if (!await confirm(context, 'Log out all users?', 'All users must request access and be approved again.', yes: 'Log out all')) return;
                await _do(Users.forceLogoutAll, 'All user phones will be logged out');
              },
            ),
          ],
        ]),
      ),
    );
  }

  /// The admin chooses the NGO roles of a person (one or more) and the branch the person works in.
  Future<void> _editRoles(Map<String, dynamic> m) async {
    final chosen = {for (final r in (m['roles'] as List? ?? const [])) '$r'};
    final branches = await Store.branches();
    var branch = '${m['branch'] ?? ''}';
    if (!branches.any((b) => b.id == branch)) branch = '';
    if (!mounted) return;
    final result = await showDialog<({List<String> roles, String branch})>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text('Access - ${'${m['name']}'.isEmpty ? m['mobile'] : m['name']}'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Branch', style: TextStyle(fontWeight: FontWeight.w700)),
              DropdownButtonFormField<String>(
                initialValue: branch,
                isExpanded: true,
                items: [const DropdownMenuItem(value: '', child: Text('All branches')), for (final b in branches) DropdownMenuItem(value: b.id, child: Text(b.s('name')))],
                onChanged: (v) => branch = v ?? '',
              ),
              const SizedBox(height: 4),
              const Text('A person assigned to a branch only sees and edits that branch.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 12),
              const Text('Roles', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final e in roleLabels.entries)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  value: chosen.contains(e.key),
                  onChanged: (v) => set(() => v == true ? chosen.add(e.key) : chosen.remove(e.key)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, (roles: chosen.toList(), branch: branch)), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _do(() async {
      await Users.setRoles('${m['mobile']}', result.roles);
      await Users.setBranch('${m['mobile']}', result.branch);
    }, 'Saved. It applies at that person\'s next sync.');
  }

  String _statusText(String s) => switch (s) { 'approved' => 'Active', 'disabled' => 'Disabled', 'pending' => 'Waiting', 'rejected' => 'Rejected', _ => s };
}
