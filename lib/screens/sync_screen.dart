import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/cloud.dart';
import '../core/db.dart';
import '../core/sync.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

/// Shown on a patient / record / medicine that was changed on two devices at the same time.
class ConflictBanner extends StatelessWidget {
  final Rec rec;
  const ConflictBanner({super.key, required this.rec});
  @override
  Widget build(BuildContext context) => Card(
        color: Colors.deepOrange.shade100,
        margin: const EdgeInsets.all(12),
        child: ListTile(
          leading: const Icon(Icons.warning_amber, color: Colors.deepOrange),
          title: const Text('Changed on two devices', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w700)),
          subtitle: const Text('Nothing was overwritten. Choose which version to keep.', style: TextStyle(color: Colors.black87)),
          trailing: FilledButton(onPressed: () => resolveConflict(context, rec), child: const Text('Resolve')),
        ),
      );
}

String _label(String k) => k.replaceAllMapped(RegExp(r'([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}').replaceFirstMapped(RegExp(r'^.'), (m) => m[0]!.toUpperCase());

String _show(dynamic v) => v == null || (v is String && v.isEmpty) ? '(empty)' : (v is List ? v.join(', ') : '$v');

/// Shows both versions side by side (only the fields that differ) and lets the user keep one.
Future<void> resolveConflict(BuildContext context, Rec r) async {
  final other = r.conflict;
  if (other == null) return;
  final theirs = Map<String, dynamic>.from(other['data'] as Map);
  final keys = {...r.data.keys, ...theirs.keys}.where((k) => _show(r.data[k]) != _show(theirs[k])).toList();
  final otherDel = other['deleted'] == true;
  final choice = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Choose the version to keep'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(shrinkWrap: true, children: [
          Text('Other device: ${(other['by'] ?? '').toString().isEmpty ? 'someone' : other['by']} · ${fmtDateTime(other['updatedAt'] as String?)}\nThis device: ${r.by} · ${fmtDateTime(r.updatedAt)}', style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 10),
          if (otherDel != r.deleted) Text(otherDel ? 'The other device DELETED this record.' : 'This device deleted this record; the other device edited it.', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.red)),
          for (final k in keys) ...[
            Text(_label(k), style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('This device:  ${_show(r.data[k])}'),
            Text('Other device: ${_show(theirs[k])}'),
            const Divider(),
          ],
          if (keys.isEmpty && otherDel == r.deleted) const Text('Both versions look the same; keeping either one resolves it.'),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Decide later')),
        OutlinedButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep other device')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Keep this device')),
      ],
    ),
  );
  if (choice == null) return;
  await SyncEngine.instance.resolve(r, keepMine: choice);
  if (context.mounted) toast(context, 'Conflict resolved');
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool _busy = false;

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final msg = await SyncEngine.instance.syncNow(manual: true, withUsers: true);
      if (mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, Sheets.explain(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SyncEngine.instance;
    final app = AppState.instance;
    return SkyScaffold(
      appBar: AppBar(title: const Text('Synchronization status')),
      body: ListenableBuilder(
        listenable: Listenable.merge([s.pending, s.running, s.connected, s.tick, s.conflictCount]),
        builder: (context, _) => ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Column(children: [
              _row(Icons.table_chart_outlined, 'Google Sheet', app.isLocal ? 'Local mode (no spreadsheet)' : (s.running.value ? 'Syncing...' : (s.connected.value ? 'Connected' : (s.lastSync == null ? 'Not reached yet' : 'Not reachable right now')))),
              _row(Icons.cloud_upload_outlined, 'Pending synchronization', '${s.pending.value} change${s.pending.value == 1 ? '' : 's'}'),
              _row(Icons.warning_amber, 'Conflicts to resolve', '${s.conflictCount.value}'),
              _row(Icons.check_circle_outline, 'Last successful sync', fmtDateTime(s.lastSync)),
              if (s.lastError != null) _row(Icons.error_outline, 'Last problem', s.lastError!),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_busy || app.isLocal) ? null : _sync,
            icon: _busy ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            label: const Text('Sync Now'),
          ),
          const SectionTitle('Conflicts'),
          Live<List<Rec>>(
            load: () => Db.instance.conflicts(app.orgId),
            builder: (c, list) => list.isEmpty
                ? const Padding(padding: EdgeInsets.all(8), child: Text('No conflicts.'))
                : Column(children: [
                    for (final r in list)
                      ListTile(
                        leading: const Icon(Icons.warning_amber, color: Colors.deepOrange),
                        title: Text(r.s('name').isNotEmpty ? r.s('name') : (r.s('title').isNotEmpty ? r.s('title') : r.type)),
                        subtitle: Text('${r.type} · changed on two devices'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => resolveConflict(context, r),
                      ),
                  ]),
          ),
          const SectionTitle('How syncing works'),
          const Text(
            'Every change is saved on this phone first, so the app works without internet. When the internet is on, this phone sends its changes '
            'to your organization\'s Google Sheet and downloads what other phones changed, so the sheet and all phones end up the same. '
            'It happens automatically after each change and every 2 hours; Sync Now does it immediately.\n\n'
            'If the same record was changed on two phones while they were apart, both versions are kept and you decide which to keep (a conflict).',
            style: TextStyle(fontSize: 13),
          ),
        ]),
      ),
    );
  }

  Widget _row(IconData i, String k, String v) => ListTile(dense: true, leading: Icon(i), title: Text(k), subtitle: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)));
}
