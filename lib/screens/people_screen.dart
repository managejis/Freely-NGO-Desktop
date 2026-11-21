import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'record_form.dart';

const _personFields = [
  FieldSpec('kind', 'Staff or volunteer', type: FT.choice, options: personKinds, required: true),
  FieldSpec('name', 'Full name', required: true),
  FieldSpec('phone', 'Phone', type: FT.phone),
  FieldSpec('designation', 'Designation'),
  FieldSpec('department', 'Department'),
  FieldSpec('branchId', 'Assigned branch', type: FT.branch, required: true),
  FieldSpec('joinDate', 'Joining date', type: FT.date),
  FieldSpec('status', 'Status', type: FT.choice, options: personStatuses, required: true),
  FieldSpec('address', 'Address', type: FT.multi),
  FieldSpec('emergencyContact', 'Emergency contact'),
  FieldSpec('responsibilities', 'Assigned responsibilities / activities', type: FT.multi),
];

/// Staff and volunteers.
class PeopleScreen extends StatefulWidget {
  const PeopleScreen({super.key});
  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  String _q = '';
  String? _kind;

  void _edit([Rec? ex]) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            title: ex == null ? 'Add staff / volunteer' : 'Edit ${ex.s('name')}',
            fields: _personFields,
            initial: ex?.data ?? {'status': 'Active', 'joinDate': dateStr(today()), if (_kind != null) 'kind': _kind},
            onSave: (d) => Store.save(tPerson, id: ex?.id, data: d, summary: '${d['kind']} ${d['name']}').then((_) {}),
          ),
        ),
      );

  Future<List<Rec>> _load() async {
    await Store.loadBranchNames();
    return Store.people();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = Perms.editPeople;
    return SkyScaffold(
      appBar: AppBar(title: const Text('Staff and volunteers')),
      floatingActionButton: canEdit ? FloatingActionButton(tooltip: 'Add', onPressed: () => _edit(), child: const Icon(Icons.person_add_alt_1)) : null,
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 0), child: TextField(decoration: searchDecoration('Search name, phone or designation'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase()))),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: const Text('All'), selected: _kind == null, onSelected: (_) => setState(() => _kind = null))),
            for (final k in personKinds) Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(k), selected: _kind == k, onSelected: (_) => setState(() => _kind = k))),
          ]),
        ),
        Expanded(
          child: Live<List<Rec>>(
            load: _load,
            builder: (c, all) {
              final list = all.where((p) => (_kind == null || p.s('kind') == _kind) && (_q.isEmpty || '${p.s('name')} ${p.s('phone')} ${p.s('designation')}'.toLowerCase().contains(_q))).toList();
              if (list.isEmpty) return EmptyState(Icons.badge_outlined, all.isEmpty ? 'No staff or volunteers yet.' : 'Nobody matches.');
              return ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                for (final p in list)
                  InfoRow(
                    icon: p.s('kind') == 'Volunteer' ? Icons.volunteer_activism : Icons.badge_outlined,
                    color: p.s('kind') == 'Volunteer' ? accentGreen : accentSky,
                    title: p.s('name'),
                    subtitle: '${p.s('kind')}${p.s('designation').isEmpty ? '' : ' · ${p.s('designation')}'} · ${Store.branchName(p.s('branchId'))}${p.s('phone').isEmpty ? '' : '\n${p.s('phone')}'}',
                    trailing: p.s('status') == 'Active' ? null : p.s('status'),
                    onTap: canEdit ? () => _edit(p) : null,
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
