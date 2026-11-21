import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'record_form.dart';

/// Which attendance groups this person may take / see.
List<String> allowedGroups() => [
      for (final c in Perms.allowedCategories) if (c == catChild || c == catElder) c,
      if (Perms.people) ...['staff', 'volunteer'],
    ];

class AttendanceScreen extends StatelessWidget {
  const AttendanceScreen({super.key});

  Future<List<Rec>> _load() async {
    await Store.loadBranchNames();
    return Store.attendance();
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Attendance')),
      floatingActionButton: Perms.takeAttendance
          ? FloatingActionButton.extended(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TakeAttendanceScreen())), icon: const Icon(Icons.fact_check_outlined), label: const Text('Take attendance'))
          : null,
      body: Live<List<Rec>>(
        load: _load,
        builder: (c, list) {
          final groups = allowedGroups();
          final shown = list.where((a) => groups.contains(a.s('group')) || groups.isEmpty).toList();
          if (shown.isEmpty) return const EmptyState(Icons.fact_check_outlined, 'No attendance recorded yet.');
          return ListView(padding: const EdgeInsets.only(top: 8, bottom: 90), children: [
            for (final a in shown)
              InfoRow(
                icon: Icons.fact_check_outlined,
                color: accentGreen,
                title: '${attendanceGroups[a.s('group')] ?? a.s('group')} · ${fmtDate(a.s('date'))}',
                subtitle: '${Store.branchName(a.s('branchId'))} · taken by ${a.by}',
                trailing: '${a.data['presentCount'] ?? 0} present / ${a.data['absentCount'] ?? 0} not',
                onTap: Perms.takeAttendance ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => TakeAttendanceScreen(date: a.s('date'), branchId: a.s('branchId'), group: a.s('group')))) : null,
              ),
          ]);
        },
      ),
    );
  }
}

class TakeAttendanceScreen extends StatefulWidget {
  final String? date, branchId, group;
  const TakeAttendanceScreen({super.key, this.date, this.branchId, this.group});
  @override
  State<TakeAttendanceScreen> createState() => _TakeAttendanceScreenState();
}

class _TakeAttendanceScreenState extends State<TakeAttendanceScreen> {
  late String _date = widget.date ?? dateStr(today());
  String? _branch, _group;
  List<Rec> _branches = [], _people = [];
  Map<String, String> _marks = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final groups = allowedGroups();
    _group = widget.group ?? (groups.isEmpty ? null : groups.first);
    _branch = widget.branchId ?? (AppState.instance.branch.isNotEmpty ? AppState.instance.branch : null);
    Store.branches().then((b) {
      _branches = b;
      if (_branch == null && b.length == 1) _branch = b.first.id;
      _reload();
    });
  }

  Future<void> _reload() async {
    final g = _group, b = _branch;
    if (g == null || b == null) return setState(() => _people = []);
    final List<Rec> people;
    if (g == 'staff' || g == 'volunteer') {
      people = (await Store.people(kind: g == 'staff' ? 'Staff' : 'Volunteer')).where((p) => p.s('branchId') == b && p.s('status') != 'Left').toList();
    } else {
      people = (await Store.beneficiaries(category: g, branchId: b)).where((x) => x.s('status') == 'Active').toList();
    }
    final existing = await Db.instance.get(Store.attendanceId(_date, b, g));
    final old = <String, String>{};
    if (g == 'staff' || g == 'volunteer') {
      // approved leave covering this date is pre-filled as "On leave"
      for (final l in await Store.approvedLeaveOn(_date)) {
        for (final p in people) {
          final byId = l.s('personId') == p.id;
          final byPhone = l.s('personId').isEmpty && normMobile(p.s('phone')).isNotEmpty && normMobile(p.s('phone')) == normMobile(l.s('enteredBy'));
          if (byId || byPhone) old[p.id] = 'On leave';
        }
      }
    }
    if (existing != null && !existing.deleted) {
      (existing.data['marks'] as Map? ?? const {}).forEach((k, v) => old['$k'] = '$v');
    }
    if (!mounted) return;
    setState(() {
      _people = people;
      _marks = {for (final p in people) p.id: old[p.id] ?? 'Present'};
    });
  }

  Future<void> _save() async {
    final b = _branch, g = _group;
    if (b == null || g == null) return;
    setState(() => _busy = true);
    final present = _marks.values.where((v) => v == 'Present').length;
    await Store.save(tAttendance, id: Store.attendanceId(_date, b, g), summary: '${attendanceGroups[g]} attendance $_date: $present present', data: {
      'date': _date, 'branchId': b, 'group': g, 'marks': _marks, 'names': {for (final p in _people) p.id: p.s('name')},
      'presentCount': present, 'absentCount': _marks.length - present, 'time': nowIso(),
    });
    if (mounted) {
      toast(context, 'Attendance saved');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = allowedGroups();
    final lockedBranch = AppState.instance.branch.isNotEmpty;
    return SkyScaffold(
      appBar: AppBar(title: const Text('Take attendance')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: groups.contains(_group) ? _group : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [for (final g in groups) DropdownMenuItem(value: g, child: Text(attendanceGroups[g]!))],
                  onChanged: widget.group != null ? null : (v) { _group = v; _reload(); },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: widget.date != null ? null : () async {
                    final d = await showDatePicker(context: context, initialDate: parseDate(_date) ?? today(), firstDate: DateTime(2020), lastDate: today());
                    if (d != null) { _date = dateStr(d); _reload(); }
                  },
                  child: InputDecorator(decoration: const InputDecoration(labelText: 'Date'), child: Text(fmtDate(_date))),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _branches.any((b) => b.id == _branch) ? _branch : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Branch'),
              items: [for (final b in _branches) DropdownMenuItem(value: b.id, child: Text(b.s('name')))],
              onChanged: (lockedBranch || widget.branchId != null) ? null : (v) { _branch = v; _reload(); },
            ),
          ]),
        ),
        if (_people.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(children: [
              Expanded(child: Text('${_marks.values.where((v) => v == 'Present').length} of ${_people.length} present', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => setState(() => _marks = {for (final p in _people) p.id: 'Present'}), child: const Text('All present')),
            ]),
          ),
        Expanded(
          child: _people.isEmpty
              ? EmptyState(Icons.groups_outlined, _branch == null ? 'Choose a branch and a group.' : 'Nobody to mark here yet: no active ${(attendanceGroups[_group] ?? 'people').toLowerCase()} in this branch.')
              : ListView(padding: const EdgeInsets.only(bottom: 100), children: [
                  for (final p in _people)
                    RowCard(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        child: Row(children: [
                          Expanded(child: Text(p.s('name'), style: const TextStyle(fontWeight: FontWeight.w700))),
                          DropdownButton<String>(
                            value: _marks[p.id],
                            underline: const SizedBox.shrink(),
                            style: TextStyle(fontWeight: FontWeight.w600, color: _marks[p.id] == 'Present' ? Colors.green.shade700 : Colors.deepOrange),
                            items: [for (final s in attendanceStatuses) DropdownMenuItem(value: s, child: Text(s))],
                            onChanged: (v) => setState(() => _marks[p.id] = v ?? 'Present'),
                          ),
                        ]),
                      ),
                    ),
                ]),
        ),
        if (_people.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save attendance'))),
      ]),
    );
  }
}
