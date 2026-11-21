import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/desk.dart';

import '../core/backup.dart';
import '../core/db.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

/// Asks for a password twice, creates an encrypted backup of everything on this phone (beneficiaries, attendance, donations, expenses,
/// stock history ...) and opens the share sheet so the file can be saved somewhere safe. Returns true when the backup was made.
Future<bool> backupNowFlow(BuildContext context) async {
  final a = await askText(context, 'Backup password', hint: 'At least 6 characters', obscure: true);
  if (a == null || !context.mounted) return false;
  if (a.length < 6) {
    toast(context, 'Use at least 6 characters');
    return false;
  }
  final b = await askText(context, 'Repeat the password', obscure: true);
  if (b != a) {
    if (context.mounted) toast(context, 'The passwords do not match');
    return false;
  }
  try {
    final f = await Backup.create(a);
    if (context.mounted) toast(context, 'Backup created');
    final saved = await Desk.saveBytes(p.basename(f.path), await f.readAsBytes());
    if (saved != null && context.mounted) toast(context, 'Backup saved to $saved');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, 'Backup failed: $e');
    return false;
  }
}

class BackupScreen extends StatefulWidget {
  const BackupScreen({super.key});
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false;
  int _version = 0;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on BackupError catch (e) {
      if (mounted) toast(context, e.message);
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    } finally {
      if (mounted) setState(() { _busy = false; _version++; });
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await backupNowFlow(context);
    } finally {
      if (mounted) setState(() { _busy = false; _version++; });
    }
  }

  Future<({String text, String password})?> _pickAndAsk() async {
    final pick = await FilePicker.platform.pickFiles(withData: true);
    final f = pick?.files.single;
    if (f == null || !mounted) return null;
    final pw = await askText(context, 'Backup password', obscure: true);
    if (pw == null || pw.isEmpty) return null;
    final text = f.bytes != null ? utf8.decode(f.bytes!) : await File(f.path!).readAsString();
    return (text: text, password: pw);
  }

  /// Backup verification: integrity + password + organization check, nothing is changed.
  Future<void> _verify() async {
    final r = await _pickAndAsk();
    if (r == null) return;
    await _run(() async {
      final plan = await Backup.inspect(r.text, r.password);
      await Db.instance.addBackup('verify', r.text.length, 'ok', note: 'Integrity check passed');
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Backup is valid'),
          content: Text('Created ${fmtDateTime(plan.createdAt)}.\n\n${plan.toAdd.length} records are not on this phone.\n${plan.differ.length} differ from this phone.\n${plan.same} are identical.'),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
        ),
      );
    });
  }

  Future<void> _restore() async {
    final r = await _pickAndAsk();
    if (r == null) return;
    await _run(() async {
      final plan = await Backup.inspect(r.text, r.password);   // validates before anything is applied
      if (!mounted) return;
      if (plan.toAdd.isEmpty && plan.differ.isEmpty) {
        toast(context, 'Everything in the backup is already on this phone.');
        return;
      }
      // never overwrite existing records without confirmation
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Restore backup'),
          content: Text('Backup from ${fmtDateTime(plan.createdAt)} was checked and is valid.\n\n'
              '• ${plan.toAdd.length} records will be ADDED.\n'
              '• ${plan.differ.length} records exist here but are different.\n'
              '• ${plan.same} are identical (skipped).'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            OutlinedButton(onPressed: () => Navigator.pop(c, 'add'), child: const Text('Add new only')),
            if (plan.differ.isNotEmpty) FilledButton(onPressed: () => Navigator.pop(c, 'all'), child: const Text('Add + overwrite')),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'all') {
        if (!mounted) return;
        if (!await confirm(context, 'Overwrite ${plan.differ.length} records?', 'Their current content on this phone will be replaced by the backup version.', yes: 'Overwrite')) return;
      }
      final n = await Backup.apply(plan, overwrite: choice == 'all');
      if (mounted) toast(context, 'Restored $n records');
    });
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Backup / Restore')),
      body: ListView(children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Backups are encrypted, password-protected text files with all records of the organization and how they relate. '
              'Keep the password safe: without it a backup cannot be opened.'),
        ),
        ListTile(leading: const Icon(Icons.upload_file), title: const Text('Create backup now'), subtitle: const Text('Export all data to an encrypted file and share/save it'), onTap: _busy ? null : _export),
        ListTile(leading: const Icon(Icons.verified_outlined), title: const Text('Verify a backup file'), subtitle: const Text('Check the password and integrity without restoring'), onTap: _busy ? null : _verify),
        ListTile(leading: const Icon(Icons.download_for_offline_outlined), title: const Text('Import / restore backup'), subtitle: const Text('Checks the file first; existing records are never overwritten without your confirmation'), onTap: _busy ? null : _restore),
        if (_busy) const LinearProgressIndicator(),
        const SectionTitle('Backup history'),
        FutureBuilder<List<Map<String, Object?>>>(
          key: ValueKey(_version),
          future: Db.instance.backups(),
          builder: (c, snap) {
            final list = snap.data ?? const [];
            if (list.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No backups yet.'));
            return Column(children: [
              for (final b in list)
                ListTile(
                  dense: true,
                  leading: Icon(b['status'] == 'ok' ? Icons.check_circle_outline : Icons.error_outline, color: b['status'] == 'ok' ? Colors.green : Colors.red),
                  title: Text('${b['kind']}${b['status'] == 'ok' ? '' : ' (failed)'}'),
                  subtitle: Text('${fmtDateTime(b['created_at'] as String?)}${(b['size'] as int) > 0 ? ' · ${fmtSize(b['size'] as int)}' : ''}${b['note'] == null ? '' : ' · ${b['note']}'}'),
                  trailing: (b['path'] != null)
                      ? IconButton(
                          icon: const Icon(Icons.save_alt),
                          onPressed: () async {
                            if (await Backup.fileExists(b['path'] as String?)) {
                              final src = File(b['path'] as String);
                              final saved = await Desk.saveBytes(p.basename(src.path), await src.readAsBytes());
                              if (saved != null && context.mounted) toast(context, 'Backup saved to $saved');
                            } else if (context.mounted) {
                              toast(context, 'The file no longer exists on this computer');
                            }
                          })
                      : null,
                ),
            ]);
          },
        ),
      ]),
    );
  }
}
