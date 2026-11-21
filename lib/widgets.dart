import 'dart:convert';

import 'package:flutter/material.dart';

import 'core/app_state.dart';
import 'core/db.dart';
import 'core/sync.dart';
import 'core/util.dart';
import 'ui.dart';

/// Loads data with [load] and reloads it whenever the local database changes (own edits or a sync).
class Live<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const Live({super.key, required this.load, required this.builder});
  @override
  State<Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<Live<T>> {
  T? _data;
  bool _has = false;

  @override
  void initState() {
    super.initState();
    Db.instance.changes.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    Db.instance.changes.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final d = await widget.load();
    if (mounted) setState(() { _data = d; _has = true; });
  }

  @override
  Widget build(BuildContext context) => _has ? widget.builder(context, _data as T) : const Center(child: CircularProgressIndicator());
}

/// The app's root navigator. Used so that dialogs (e.g. logout) still work after the drawer or a screen has been closed.
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

void toast(BuildContext c, String msg) =>
    ScaffoldMessenger.of(c)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg)));

Future<bool> confirm(BuildContext c, String title, String body, {String yes = 'Yes', String no = 'Cancel'}) async =>
    (await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(title: Text(title), content: Text(body), actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(no)),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(yes)),
      ]),
    )) ??
    false;

Future<String?> askText(BuildContext c, String title, {String? hint, bool obscure = false, String? initial}) async {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, obscureText: obscure, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

/// Organization logo (or a NGO icon until the admin uploads one).
class OrgAvatar extends StatelessWidget {
  final double size;
  const OrgAvatar({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final logo = AppState.instance.logo;
    if (logo != null && logo.isNotEmpty) {
      try {
        return ClipRRect(borderRadius: BorderRadius.circular(size / 5), child: Image.memory(base64Decode(logo), width: size, height: size, fit: BoxFit.cover));
      } catch (_) {}
    }
    return ClipRRect(borderRadius: BorderRadius.circular(size / 4), child: Image.asset('assets/logo.png', width: size, height: size, fit: BoxFit.cover));
  }
}

/// Small "synced / N pending / offline" indicator.
class SyncChip extends StatelessWidget {
  final VoidCallback? onTap;
  const SyncChip({super.key, this.onTap});
  @override
  Widget build(BuildContext context) {
    final s = SyncEngine.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([s.pending, s.running, s.connected, s.tick, s.conflictCount]),
      builder: (_, __) {
        String text;
        IconData icon;
        Color color;
        if (AppState.instance.isLocal) {
          text = 'Local mode (no sync)';
          icon = Icons.phone_android;
          color = Colors.blueGrey;
        } else if (s.conflictCount.value > 0) {
          text = '${s.conflictCount.value} conflict${s.conflictCount.value == 1 ? '' : 's'} to resolve';
          icon = Icons.warning_amber;
          color = Colors.deepOrange;
        } else if (s.running.value) {
          text = 'Syncing...';
          icon = Icons.sync;
          color = Colors.blue;
        } else if (!s.connected.value && s.lastSync == null) {
          text = s.pending.value > 0 ? 'Not synced - ${s.pending.value} pending' : 'Not synced yet';
          icon = Icons.cloud_off;
          color = Colors.grey.shade700;
        } else if (!s.connected.value) {
          text = s.pending.value > 0 ? 'Offline - ${s.pending.value} pending' : 'Offline';
          icon = Icons.cloud_off;
          color = Colors.grey.shade700;
        } else if (s.pending.value > 0) {
          text = '${s.pending.value} pending sync';
          icon = Icons.cloud_upload_outlined;
          color = Colors.orange.shade800;
        } else {
          text = 'Synced ${fmtDateTime(s.lastSync)}';
          icon = Icons.cloud_done_outlined;
          color = Colors.green.shade700;
        }
        return ActionChip(
          avatar: Icon(icon, size: 18, color: color),
          label: Text(text, style: TextStyle(color: color, fontSize: 12.5)),
          onPressed: onTap,
        );
      },
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: Text(text, style: serif(21, color: Theme.of(context).colorScheme.onSurface)),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}

/// A date field that opens the date picker. Value is "yyyy-MM-dd" or empty.
class DateField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;
  const DateField({super.key, required this.label, required this.controller, this.required = false});
  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          suffixIcon: controller.text.isEmpty ? const Icon(Icons.calendar_today, size: 20) : IconButton(icon: const Icon(Icons.clear), onPressed: () => controller.clear()),
        ),
        validator: required ? (v) => (v == null || v.isEmpty) ? 'Required' : null : null,
        onTap: () async {
          final d = await showDatePicker(
            context: context,
            initialDate: parseDate(controller.text) ?? today(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (d != null) controller.text = dateStr(d);
        },
      );
}
