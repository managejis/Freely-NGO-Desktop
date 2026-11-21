import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'record_form.dart';
import 'sync_screen.dart';

const _catIcons = {catChild: Icons.child_care, catElder: Icons.elderly, catPatient: Icons.medical_services_outlined};
const _catColors = {catChild: accentOrange, catElder: accentViolet, catPatient: accentPink};

List<FieldSpec> beneficiaryFields(String cat) => [
      const FieldSpec('name', 'Full name', required: true),
      const FieldSpec('dob', 'Date of birth', type: FT.date),
      const FieldSpec('gender', 'Gender', type: FT.choice, options: genders, required: true),
      const FieldSpec('branchId', 'Home / branch', type: FT.branch, required: true),
      FieldSpec('admissionDate', cat == catPatient ? 'Registration date' : 'Admission date', type: FT.date, required: true),
      if (cat == catChild) ...const [
        FieldSpec('education', 'School and class'),
        FieldSpec('guardianName', 'Parent / guardian name'),
        FieldSpec('guardianPhone', 'Parent / guardian phone', type: FT.phone),
      ],
      if (cat == catElder) ...const [
        FieldSpec('room', 'Room / bed'),
        FieldSpec('address', 'Previous address', type: FT.multi),
        FieldSpec('guardianName', 'Family member name'),
        FieldSpec('guardianPhone', 'Family member phone', type: FT.phone),
      ],
      if (cat == catPatient) ...const [
        FieldSpec('phone', 'Contact phone', type: FT.phone),
        FieldSpec('address', 'Address', type: FT.multi),
        FieldSpec('coordinator', 'Assigned coordinator'),
      ],
      const FieldSpec('emergencyName', 'Emergency contact name'),
      const FieldSpec('emergencyPhone', 'Emergency contact phone', type: FT.phone),
      FieldSpec('special', cat == catPatient ? 'Assistance required' : (cat == catChild ? 'Special requirements / care needs' : 'Mobility, diet and special requirements'), type: FT.multi),
      const FieldSpec('notes', 'Notes', type: FT.multi),
    ];

Future<void> startRegistration(BuildContext context, {String? category}) async {
  var cat = category;
  if (cat == null) {
    final opts = Perms.allowedCategories;
    if (opts.length == 1) {
      cat = opts.first;
    } else {
      cat = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('Register a ...', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
            for (final o in opts) ListTile(leading: Icon(_catIcons[o], color: _catColors[o]), title: Text(categoryLabels[o]!), onTap: () => Navigator.pop(c, o)),
            const SizedBox(height: 8),
          ]),
        ),
      );
    }
  }
  if (cat == null || !context.mounted) return;
  Navigator.push(context, MaterialPageRoute(builder: (_) => BeneficiaryEditScreen(category: cat!)));
}

// ====================================================================== list
class BeneficiariesScreen extends StatefulWidget {
  final String? category;
  const BeneficiariesScreen({super.key, this.category});
  @override
  State<BeneficiariesScreen> createState() => _BeneficiariesScreenState();
}

class _BeneficiariesScreenState extends State<BeneficiariesScreen> {
  String _q = '';
  String _status = 'Active';
  String? _cat;

  @override
  void initState() {
    super.initState();
    _cat = widget.category;
  }

  Future<List<Rec>> _load() async {
    await Store.loadBranchNames();
    return Store.beneficiaries();
  }

  @override
  Widget build(BuildContext context) {
    final cats = Perms.allowedCategories;
    return SkyScaffold(
      appBar: AppBar(title: Text(widget.category == null ? 'Beneficiaries' : categoryPlural[widget.category]!)),
      floatingActionButton: Perms.editBeneficiaries ? FloatingActionButton(tooltip: 'Register', onPressed: () => startRegistration(context, category: _cat), child: const Icon(Icons.person_add_alt_1)) : null,
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 0), child: TextField(decoration: searchDecoration('Search name, ID or phone'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase()))),
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
            if (widget.category == null && cats.length > 1) ...[
              Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: const Text('All'), selected: _cat == null, onSelected: (_) => setState(() => _cat = null))),
              for (final c in cats) Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(categoryPlural[c]!), selected: _cat == c, onSelected: (_) => setState(() => _cat = c))),
              const SizedBox(width: 10),
            ],
            for (final s in ['Active', 'Discharged', 'All']) Padding(padding: const EdgeInsets.all(4), child: ChoiceChip(label: Text(s), selected: _status == s, onSelected: (_) => setState(() => _status = s))),
          ]),
        ),
        Expanded(
          child: Live<List<Rec>>(
            load: _load,
            builder: (c, all) {
              final list = all.where((b) {
                if (_cat != null && b.s('category') != _cat) return false;
                final st = b.s('status');
                if (_status == 'Active' && st != 'Active') return false;
                if (_status == 'Discharged' && st == 'Active') return false;
                if (_q.isNotEmpty && !'${b.s('name')} ${b.s('bid')} ${b.s('phone')} ${b.s('guardianPhone')}'.toLowerCase().contains(_q)) return false;
                return true;
              }).toList();
              if (list.isEmpty) return EmptyState(Icons.groups_outlined, all.isEmpty ? 'No beneficiaries yet.${Perms.editBeneficiaries ? '\nTap the button to register one.' : ''}' : 'Nobody matches.');
              return ListView.builder(
                padding: const EdgeInsets.only(top: 6, bottom: 90),
                itemCount: list.length,
                itemBuilder: (c, i) => BeneficiaryRow(b: list[i], onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BeneficiaryDetailScreen(id: list[i].id)))),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class BeneficiaryRow extends StatelessWidget {
  final Rec b;
  final VoidCallback onTap;
  const BeneficiaryRow({super.key, required this.b, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cat = b.s('category');
    final age = ageOf(b.s('dob'));
    return InfoRow(
      icon: _catIcons[cat] ?? Icons.person,
      color: _catColors[cat] ?? brandBlue,
      title: b.s('name'),
      subtitle: '${b.s('bid')}${age == null ? '' : ' · $age yrs'} · ${Store.branchName(b.s('branchId'))}',
      trailing: b.s('status') == 'Active' ? null : b.s('status'),
      onTap: onTap,
    );
  }
}

// ====================================================================== register / edit
class BeneficiaryEditScreen extends StatelessWidget {
  final String category;
  final Rec? existing;
  const BeneficiaryEditScreen({super.key, required this.category, this.existing});

  @override
  Widget build(BuildContext context) {
    final ex = existing;
    return RecordFormScreen(
      title: ex == null ? 'Register ${categoryLabels[category]!.toLowerCase()}' : 'Edit ${ex.s('name')}',
      fields: beneficiaryFields(category),
      initial: ex?.data ?? {'category': category, 'status': 'Active', 'bid': Store.newBeneficiaryId(category), 'admissionDate': dateStr(today())},
      onSave: (d) async {
        if (ex == null) {
          d['history'] = [
            {'event': 'Admitted', 'date': d['admissionDate'] ?? dateStr(today()), 'branchId': d['branchId'], 'by': AppState.instance.mobile},
          ];
        }
        await Store.save(tBeneficiary, id: ex?.id, data: d, summary: '${categoryLabels[category]} ${d['name']} (${d['bid']})');
      },
    );
  }
}

// ====================================================================== detail
class BeneficiaryDetailScreen extends StatefulWidget {
  final String id;
  const BeneficiaryDetailScreen({super.key, required this.id});
  @override
  State<BeneficiaryDetailScreen> createState() => _BeneficiaryDetailScreenState();
}

class _Detail {
  final Rec? b;
  final List<Rec> medical, care, safe;
  _Detail(this.b, this.medical, this.care, this.safe);
}

class _BeneficiaryDetailScreenState extends State<BeneficiaryDetailScreen> {
  bool _audited = false;

  Future<_Detail> _load() async {
    await Store.loadBranchNames();
    final b = await Db.instance.get(widget.id);
    final med = Perms.medical ? await Store.forBeneficiary(tMedical, widget.id) : <Rec>[];
    final care = Perms.care ? await Store.forBeneficiary(tCare, widget.id) : <Rec>[];
    final safe = Perms.safeguard ? await Store.forBeneficiary(tSafeguard, widget.id) : <Rec>[];
    if (!_audited && b != null && (Perms.medical || Perms.safeguard)) {
      _audited = true;   // viewing sensitive information is logged
      Store.auditAccess(tBeneficiary, b.id, 'Opened record of ${b.s('name')} (${b.s('bid')})');
    }
    return _Detail(b, med, care, safe);
  }

  Future<void> _history(Rec b, Map<String, dynamic> entry, Map<String, dynamic> changes, String summary) async {
    final h = [...((b.data['history'] as List?) ?? const []), {...entry, 'by': AppState.instance.mobile}];
    await Store.save(tBeneficiary, id: b.id, data: {...b.data, ...changes, 'history': h}, summary: summary);
  }

  Future<void> _discharge(Rec b) async {
    final date = TextEditingController(text: dateStr(today()));
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Discharge ${b.s('name')}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DateField(label: 'Discharge date', controller: date, required: true),
          const SizedBox(height: 10),
          TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason / destination (family, hospital, ...)')),
        ]),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discharge'))],
      ),
    );
    if (ok != true || date.text.isEmpty) return;
    await _history(b, {'event': 'Discharged', 'date': date.text, 'note': reason.text.trim(), 'branchId': b.s('branchId')}, {'status': 'Discharged', 'dischargeDate': date.text}, 'Discharged ${b.s('name')} (${b.s('bid')})');
  }

  Future<void> _readmit(Rec b) async {
    if (!await confirm(context, 'Admit ${b.s('name')} again?', 'The earlier admission stays in the history. No duplicate registration is created.', yes: 'Admit')) return;
    await _history(b, {'event': 'Re-admitted', 'date': dateStr(today()), 'branchId': b.s('branchId')}, {'status': 'Active', 'dischargeDate': '', 'admissionDate': dateStr(today())}, 'Re-admitted ${b.s('name')} (${b.s('bid')})');
  }

  Future<void> _transfer(Rec b) async {
    final branches = (await Store.branches()).where((x) => x.id != b.s('branchId')).toList();
    if (!mounted) return;
    if (branches.isEmpty) return toast(context, 'There is no other branch to transfer to.');
    final to = await showDialog<Rec>(
      context: context,
      builder: (c) => SimpleDialog(title: const Text('Transfer to'), children: [for (final x in branches) SimpleDialogOption(onPressed: () => Navigator.pop(c, x), child: Text(x.s('name')))]),
    );
    if (to == null) return;
    await _history(b, {'event': 'Transferred', 'date': dateStr(today()), 'branchId': to.id, 'note': 'from ${Store.branchName(b.s('branchId'))}'}, {'branchId': to.id, 'status': 'Active'}, 'Transferred ${b.s('name')} to ${to.s('name')}');
  }

  Future<void> _addRecord(Rec b, String type, {Rec? existing}) async {
    final kinds = type == tMedical ? medicalKinds : (type == tCare ? careKinds : safeguardKinds);
    final fields = [
      FieldSpec('kind', 'Type', type: FT.choice, options: kinds, required: true),
      const FieldSpec('date', 'Date', type: FT.date, required: true),
      if (type == tMedical) const FieldSpec('value', 'Reading / value (BP 120/80, weight 24 kg ...)'),
      const FieldSpec('notes', 'Details', type: FT.multi),
      if (type != tSafeguard) const FieldSpec('nextFollowUp', 'Next follow-up date', type: FT.date),
      if (type == tCare) const FieldSpec('staff', 'Staff / volunteer'),
    ];
    final titles = {tMedical: 'medical record', tCare: 'care record', tSafeguard: 'safeguarding record'};
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormScreen(
      title: existing == null ? 'Add ${titles[type]}' : 'Edit ${titles[type]}',
      fields: fields,
      initial: existing?.data ?? {'date': dateStr(today()), 'beneficiaryId': b.id, 'beneficiaryName': b.s('name'), 'category': b.s('category'), 'branchId': b.s('branchId')},
      onSave: (d) async {
        await Store.save(type, id: existing?.id, data: d, summary: '${d['kind']} for ${b.s('name')}');
        if (type == tSafeguard && d['kind'] == 'Death record' && b.s('status') != 'Deceased') {
          await _history(b, {'event': 'Deceased', 'date': d['date'], 'branchId': b.s('branchId')}, {'status': 'Deceased', 'dischargeDate': d['date']}, 'Death recorded for ${b.s('name')}');
        }
      },
    )));
  }

  Widget _records(String title, List<Rec> list, Rec b, String type, bool canWrite, IconData icon, Color color) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: SectionTitle('$title (${list.length})')),
        if (canWrite) IconButton(tooltip: 'Add', icon: const Icon(Icons.add_circle, color: brandBlue), onPressed: () => _addRecord(b, type)),
      ]),
      if (list.isEmpty) const Padding(padding: EdgeInsets.symmetric(horizontal: 18), child: Text('Nothing recorded yet.')),
      for (final r in list)
        InfoRow(
          icon: icon,
          color: color,
          title: '${r.s('kind')}${r.s('value').isEmpty ? '' : ' · ${r.s('value')}'}',
          subtitle: '${fmtDate(r.s('date'))}${r.s('notes').isEmpty ? '' : '\n${r.s('notes')}'}${r.s('nextFollowUp').isEmpty ? '' : '\nFollow-up: ${fmtDate(r.s('nextFollowUp'))}${r.data['followDone'] == true ? ' (done)' : ''}'}',
          onTap: canWrite ? () => _recordMenu(b, r, type) : null,
        ),
    ]);
  }

  Future<void> _recordMenu(Rec b, Rec r, String type) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Edit'), onTap: () => Navigator.pop(c, 'edit')),
          if (r.s('nextFollowUp').isNotEmpty && r.data['followDone'] != true) ListTile(leading: const Icon(Icons.check_circle_outline), title: const Text('Mark follow-up done'), onTap: () => Navigator.pop(c, 'done')),
          ListTile(leading: const Icon(Icons.delete_outline, color: Colors.red), title: const Text('Delete'), onTap: () => Navigator.pop(c, 'delete')),
        ]),
      ),
    );
    if (v == 'edit') {
      await _addRecord(b, type, existing: r);
    } else if (v == 'done') {
      await Store.save(type, id: r.id, data: {...r.data, 'followDone': true}, summary: 'Follow-up done for ${b.s('name')}');
    } else if (v == 'delete' && mounted && await confirm(context, 'Delete this record?', '${r.s('kind')} · ${fmtDate(r.s('date'))}', yes: 'Delete')) {
      await Store.remove(r, '${r.s('kind')} record of ${b.s('name')}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Live<_Detail>(
      load: _load,
      builder: (c, d) {
        final b = d.b;
        if (b == null || b.deleted) return SkyScaffold(appBar: AppBar(), body: const EmptyState(Icons.person_off_outlined, 'This record is no longer available.'));
        final cat = b.s('category');
        final age = ageOf(b.s('dob'));
        final canEdit = Perms.editBeneficiaries;
        final history = ((b.data['history'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList().reversed.toList();
        Widget kv(String k, String v) => v.isEmpty ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: 130, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))), Expanded(child: Text(v))]));
        return SkyScaffold(
          appBar: AppBar(title: Text(b.s('name'))),
          body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            if (b.conflict != null) ConflictBanner(rec: b),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: gradientOf(cat == catChild ? gOrange : (cat == catElder ? gPurple : gPink)), borderRadius: BorderRadius.circular(26)),
              child: Row(children: [
                Container(width: 58, height: 58, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: Icon(_catIcons[cat], color: _catColors[cat], size: 32)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(b.s('name'), style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  Text('${b.s('bid')} · ${categoryLabels[cat]}${age == null ? '' : ' · $age yrs'}', style: const TextStyle(color: Colors.white)),
                  Text('${Store.branchName(b.s('branchId'))} · ${b.s('status')}', style: const TextStyle(color: Colors.white70)),
                ])),
              ]),
            ),
            if (canEdit)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BeneficiaryEditScreen(category: cat, existing: b)))),
                  if (b.s('status') == 'Active') OutlinedButton.icon(icon: const Icon(Icons.logout, size: 18), label: const Text('Discharge'), onPressed: () => _discharge(b)),
                  if (b.s('status') == 'Discharged' || b.s('status') == 'Transferred') OutlinedButton.icon(icon: const Icon(Icons.login, size: 18), label: const Text('Admit again'), onPressed: () => _readmit(b)),
                  if (AppState.instance.branch.isEmpty && b.s('status') == 'Active') OutlinedButton.icon(icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Transfer'), onPressed: () => _transfer(b)),
                ]),
              ),
            const SectionTitle('Profile'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(children: [
                kv('Gender', b.s('gender')),
                kv('Date of birth', b.s('dob').isEmpty ? '' : fmtDate(b.s('dob'))),
                kv('Admitted', b.s('admissionDate').isEmpty ? '' : fmtDate(b.s('admissionDate'))),
                kv('Discharged', b.s('dischargeDate').isEmpty ? '' : fmtDate(b.s('dischargeDate'))),
                kv('Education', b.s('education')),
                kv('Room / bed', b.s('room')),
                kv('Phone', b.s('phone')),
                kv('Address', b.s('address')),
                kv(cat == catChild ? 'Guardian' : 'Family', '${b.s('guardianName')} ${b.s('guardianPhone')}'.trim()),
                kv('Emergency contact', '${b.s('emergencyName')} ${b.s('emergencyPhone')}'.trim()),
                kv('Coordinator', b.s('coordinator')),
                kv('Special needs', b.s('special')),
                kv('Notes', b.s('notes')),
              ]),
            ),
            SectionTitle('Admission history (${history.length})'),
            for (final h in history)
              ListTile(dense: true, leading: const Icon(Icons.timeline, color: brandBlue), title: Text('${h['event']} · ${fmtDate('${h['date']}')}'), subtitle: Text('${Store.branchName('${h['branchId'] ?? ''}')}${('${h['note'] ?? ''}').isEmpty ? '' : ' · ${h['note']}'}')),
            if (Perms.care) _records('Care and activities', d.care, b, tCare, Perms.writeCare, Icons.volunteer_activism_outlined, accentGreen),
            if (Perms.medical) _records('Medical records', d.medical, b, tMedical, Perms.writeMedical, Icons.medical_information_outlined, accentPink),
            if (Perms.safeguard) _records('Safeguarding and incidents (restricted)', d.safe, b, tSafeguard, Perms.writeSafeguard, Icons.shield_outlined, accentOrange),
          ]),
        );
      },
    );
  }
}
