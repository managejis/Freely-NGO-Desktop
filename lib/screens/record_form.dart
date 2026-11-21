import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/store.dart';
import '../ui.dart';
import '../widgets.dart';

enum FT { text, multi, number, date, choice, phone, branch, yesno }

class FieldSpec {
  final String key, label;
  final FT type;
  final List<String> options;
  final bool required;
  final String? hint;
  const FieldSpec(this.key, this.label, {this.type = FT.text, this.options = const [], this.required = false, this.hint});
}

/// One form for every kind of record: the fields are described by [FieldSpec]s, the screen builds the inputs, validates them
/// and hands the entered values to [onSave]. Values of fields that are not in the form (e.g. history) are kept from [initial].
class RecordFormScreen extends StatefulWidget {
  final String title;
  final List<FieldSpec> fields;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> data) onSave;
  final String saveLabel;
  const RecordFormScreen({super.key, required this.title, required this.fields, required this.onSave, this.initial = const {}, this.saveLabel = 'Save'});
  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  final _form = GlobalKey<FormState>();
  final _ctl = <String, TextEditingController>{};
  final _val = <String, dynamic>{};     // choice / branch / yesno values
  List<Rec> _branches = [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final myBranch = AppState.instance.branch;
    for (final f in widget.fields) {
      final v = widget.initial[f.key];
      switch (f.type) {
        case FT.choice:
          _val[f.key] = f.options.contains('${v ?? ''}') ? '$v' : null;
        case FT.branch:
          _val[f.key] = ('${v ?? ''}'.isNotEmpty ? '$v' : (myBranch.isNotEmpty ? myBranch : null));
        case FT.yesno:
          _val[f.key] = v == true;
        default:
          _ctl[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
    }
    Store.branches().then((b) {
      if (mounted) setState(() => _branches = b);
    });
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final out = <String, dynamic>{...widget.initial};
    for (final f in widget.fields) {
      switch (f.type) {
        case FT.choice || FT.branch:
          out[f.key] = _val[f.key] ?? '';
        case FT.yesno:
          out[f.key] = _val[f.key] == true;
        case FT.number:
          final t = _ctl[f.key]!.text.trim().replaceAll(',', '');
          out[f.key] = t.isEmpty ? null : (num.tryParse(t) ?? 0);
        default:
          out[f.key] = _ctl[f.key]!.text.trim();
      }
    }
    setState(() => _busy = true);
    try {
      await widget.onSave(out);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, '$e');
      }
    }
  }

  Widget _input(FieldSpec f) {
    final label = f.label + (f.required ? ' *' : '');
    switch (f.type) {
      case FT.date:
        return DateField(label: f.label, controller: _ctl[f.key]!, required: f.required);
      case FT.choice:
        return DropdownButtonFormField<String>(
          initialValue: _val[f.key] as String?,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final o in f.options) DropdownMenuItem(value: o, child: Text(o))],
          onChanged: (v) => _val[f.key] = v,
          validator: f.required ? (v) => v == null ? 'Required' : null : null,
        );
      case FT.branch:
        final locked = AppState.instance.branch.isNotEmpty;
        return DropdownButtonFormField<String>(
          initialValue: _branches.any((b) => b.id == _val[f.key]) ? _val[f.key] as String : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.s('name')))],
          onChanged: locked ? null : (v) => _val[f.key] = v,
          validator: f.required ? (v) => (v == null || v.isEmpty) ? 'Choose a branch (the admin creates branches first)' : null : null,
        );
      case FT.yesno:
        return StatefulBuilder(builder: (c, set) => SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(f.label), value: _val[f.key] == true, onChanged: (v) => set(() => _val[f.key] = v)));
      default:
        return TextFormField(
          controller: _ctl[f.key],
          minLines: f.type == FT.multi ? 3 : 1,
          maxLines: f.type == FT.multi ? 6 : 1,
          textCapitalization: f.type == FT.phone ? TextCapitalization.none : TextCapitalization.sentences,
          keyboardType: f.type == FT.number ? const TextInputType.numberWithOptions(decimal: true) : (f.type == FT.phone ? TextInputType.phone : TextInputType.text),
          decoration: InputDecoration(labelText: label, hintText: f.hint),
          validator: (v) {
            final t = (v ?? '').trim();
            if (f.required && t.isEmpty) return 'Required';
            if (f.type == FT.number && t.isNotEmpty && num.tryParse(t.replaceAll(',', '')) == null) return 'Enter a number';
            return null;
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) => SkyScaffold(
        maxWidth: 760,
        appBar: AppBar(title: Text(widget.title)),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final f in widget.fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: _input(f)),
            const SizedBox(height: 8),
            FilledButton(onPressed: _busy ? null : _save, child: _busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.saveLabel)),
            const SizedBox(height: 24),
          ]),
        ),
      );
}

/// Small helper: a card row used by the list screens.
class InfoRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool strike;
  const InfoRow({super.key, required this.icon, required this.title, this.subtitle = '', this.trailing, this.color = brandBlue, this.onTap, this.strike = false});
  @override
  Widget build(BuildContext context) => RowCard(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: color)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, decoration: strike ? TextDecoration.lineThrough : null)),
                if (subtitle.isNotEmpty) Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.outline)),
              ]),
            ),
            if (trailing != null) Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}
