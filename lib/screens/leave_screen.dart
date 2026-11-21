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

const _red = Color(0xFFC62828);

Color _statusColor(String s) => switch (s) { 'requested' => accentOrange, 'verified' => accentSky, 'approved' => accentGreen, _ => _red };

const _leaveFields = [
  FieldSpec('leaveType', 'Type of leave', type: FT.choice, options: leaveTypes, required: true),
  FieldSpec('fromDate', 'From', type: FT.date, required: true),
  FieldSpec('toDate', 'To (last day of leave)', type: FT.date, required: true),
  FieldSpec('reason', 'Reason', type: FT.multi),
  FieldSpec('branchId', 'Branch', type: FT.branch, required: true),
];

class _LeaveData {
  final List<Rec> leaves, people;
  _LeaveData(this.leaves, this.people);
}

/// Leave of staff and volunteers. Everybody can request leave; a manager verifies, the administrator approves.
/// Approved leave shows as "On leave" when staff attendance is taken.
class LeaveScreen extends StatefulWidget {
  const LeaveScreen({super.key});
  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  String _filter = 'open';

  bool _mine(Rec l) => l.s('enteredBy') == Store.me;

  Future<_LeaveData> _load() async {
    await Store.loadBranchNames();
    return _LeaveData(await Store.leaves(), Perms.editPeople ? await Store.people() : <Rec>[]);
  }

  /// Does [l] belong to the same person as the request being made?
  bool _same(Rec l, String personId) => personId.isNotEmpty ? l.s('personId') == personId : (l.s('personId').isEmpty && _mine(l));

  Future<void> _request(_LeaveData d, {Rec? existing}) async {
    var personId = existing?.s('personId') ?? '';
    var personName = existing?.s('personName') ?? AppState.instance.userName;
    if (existing == null && Perms.editPeople && d.people.isNotEmpty) {
      // a manager can record leave on behalf of a staff member or volunteer
      final pick = await showDialog<Rec?>(
        context: context,
        builder: (c) => SimpleDialog(title: const Text('Leave for'), children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(c, null), child: const Text('Myself')),
          for (final p in d.people.where((x) => x.s('status') != 'Left')) SimpleDialogOption(onPressed: () => Navigator.pop(c, p), child: Text('${p.s('name')} (${p.s('kind')})')),
        ]),
      );
      if (!mounted) return;
      if (pick != null) {
        personId = pick.id;
        personName = pick.s('name');
      }
    }
    final pid = personId, pname = personName;
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormScreen(
      title: existing == null ? 'Request leave' : 'Edit leave request',
      fields: _leaveFields,
      initial: existing?.data ?? {'fromDate': dateStr(today()), 'toDate': dateStr(today()), 'leaveType': 'Casual leave'},
      onSave: (x) async {
        final from = '${x['fromDate']}', to = '${x['toDate']}';
        final days = Store.leaveDays(from, to);
        if (days == 0) throw 'The last day of leave must be on or after the first day.';
        final all = (await Store.leaves()).where((l) => _same(l, pid) && l.id != existing?.id && {'requested', 'verified', 'approved'}.contains(Store.leaveStatus(l))).toList();
        for (final l in all) {
          if (from.compareTo(l.s('toDate')) <= 0 && to.compareTo(l.s('fromDate')) >= 0) {
            throw 'These dates overlap leave already ${leaveStatusLabels[Store.leaveStatus(l)]!.toLowerCase()} (${fmtDate(l.s('fromDate'))} - ${fmtDate(l.s('toDate'))}).';
          }
        }
        final ent = leaveEntitlement[x['leaveType']];
        final fy = Store.fyOf(parseDate(from)!);
        if (ent != null) {
          final used = all.where((l) => l.s('leaveType') == x['leaveType'] && parseDate(l.s('fromDate')) != null && Store.fyOf(parseDate(l.s('fromDate'))!) == fy).fold<int>(0, (a, l) => a + l.i('days'));
          if (used + days > ent) throw 'Only ${ent - used} day${ent - used == 1 ? '' : 's'} of ${x['leaveType'].toString().toLowerCase()} left for $fy-${(fy + 1) % 100} (including pending requests).';
        }
        await Store.save(tLeave, id: existing?.id, summary: 'Leave $pname $from..$to ($days days)', data: {
          ...x, 'days': days, 'status': existing == null ? 'requested' : Store.leaveStatus(existing),
          'enteredBy': existing?.s('enteredBy').isNotEmpty == true ? existing!.s('enteredBy') : Store.me, 'personId': pid, 'personName': pname,
        });
      },
    )));
  }

  Future<void> _step(Rec l, String to, String question) async {
    if (!await confirm(context, question, '${l.s('personName')} · ${l.s('leaveType')} · ${fmtDate(l.s('fromDate'))} - ${fmtDate(l.s('toDate'))} (${l.i('days')} days)', yes: leaveStatusLabels[to] ?? 'Yes')) return;
    await Store.advanceLeave(l, to);
  }

  void _sheet(Rec l, _LeaveData d) {
    final st = Store.leaveStatus(l);
    final mine = _mine(l);
    final admin = AppState.instance.isAdmin;
    final others = !mine || admin;      // nobody verifies or approves their own request (the Super Admin excepted)
    String who(String k) => l.s(k).isEmpty ? '' : '\n$k: ${l.s(k)} (${fmtDateTime(l.s('${k}At'))})';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${l.s('personName')} · ${l.i('days')} day${l.i('days') == 1 ? '' : 's'}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Chip(label: Text(leaveStatusLabels[st] ?? st), backgroundColor: _statusColor(st).withValues(alpha: 0.25)),
            Text('${l.s('leaveType')}\n${fmtDate(l.s('fromDate'))} - ${fmtDate(l.s('toDate'))} · ${Store.branchName(l.s('branchId'))}'
                '${l.s('reason').isEmpty ? '' : '\n${l.s('reason')}'}\nRequested by: ${l.s('enteredBy')}${who('verifiedBy')}${who('approvedBy')}${who('rejectedBy')}${who('cancelledBy')}'),
            if (l.conflict != null) ConflictBanner(rec: l),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 8, children: [
              if (st == 'requested' && (mine || Perms.verifyExpense)) OutlinedButton.icon(icon: const Icon(Icons.edit_outlined), label: const Text('Edit'), onPressed: () { Navigator.pop(c); _request(d, existing: l); }),
              if (st == 'requested' && Perms.verifyExpense && others) FilledButton.icon(icon: const Icon(Icons.fact_check_outlined), label: const Text('Verify'), onPressed: () { Navigator.pop(c); _step(l, 'verified', 'Verify this leave?'); }),
              if (st == 'verified' && Perms.approveExpense && others) FilledButton.icon(icon: const Icon(Icons.thumb_up_alt_outlined), label: const Text('Approve'), onPressed: () { Navigator.pop(c); _step(l, 'approved', 'Approve this leave?'); }),
              if ((st == 'requested' || st == 'verified') && Perms.verifyExpense && others)
                OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: _red), icon: const Icon(Icons.close), label: const Text('Reject'), onPressed: () { Navigator.pop(c); _step(l, 'rejected', 'Reject this leave?'); }),
              if ((st == 'requested' || st == 'verified') && mine)
                OutlinedButton.icon(icon: const Icon(Icons.undo), label: const Text('Cancel request'), onPressed: () { Navigator.pop(c); _step(l, 'cancelled', 'Cancel this request?'); }),
              if (st == 'approved' && Perms.approveExpense)
                OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: _red), icon: const Icon(Icons.event_busy), label: const Text('Cancel leave'), onPressed: () { Navigator.pop(c); _step(l, 'cancelled', 'Cancel this approved leave?'); }),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _balances(List<Rec> mineList) {
    final fy = Store.fyOf(today());
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(gradient: gradientOf(gPurple), borderRadius: BorderRadius.circular(24)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('My leave balance · FY $fy-${(fy + 1) % 100}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          for (final e in leaveEntitlement.entries)
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${e.value - Store.usedLeave(mineList.where((l) => l.s('personId').isEmpty).toList(), e.key, fy)} / ${e.value}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
                Text(e.key.replaceAll(' leave', ''), style: const TextStyle(color: Colors.white, fontSize: 11.5)),
              ]),
            ),
        ]),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Live<_LeaveData>(
      load: _load,
      builder: (c, d) {
        final list = d.leaves.where((l) {
          final st = Store.leaveStatus(l);
          return switch (_filter) { 'open' => st == 'requested' || st == 'verified', 'approved' => st == 'approved', 'closed' => st == 'rejected' || st == 'cancelled', _ => true };
        }).toList();
        final awaiting = d.leaves.where((l) => {'requested', 'verified'}.contains(Store.leaveStatus(l))).length;
        return SkyScaffold(
          appBar: AppBar(title: const Text('Leave')),
          floatingActionButton: FloatingActionButton.extended(onPressed: () => _request(d), icon: const Icon(Icons.event_busy_outlined), label: const Text('Request leave')),
          body: Column(children: [
            _balances(d.leaves.where(_mine).toList()),
            SizedBox(
              height: 54,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0), children: [
                for (final f in {'open': 'Awaiting ($awaiting)', 'approved': 'Approved', 'closed': 'Rejected / cancelled', 'all': 'All'}.entries)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(f.value), selected: _filter == f.key, onSelected: (_) => setState(() => _filter = f.key))),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(Icons.event_available_outlined, d.leaves.isEmpty ? 'No leave requests yet.\nTap "Request leave".' : 'Nothing in this list.')
                  : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                      for (final l in list)
                        InfoRow(
                          icon: Icons.event_busy_outlined,
                          color: _statusColor(Store.leaveStatus(l)),
                          title: '${l.s('personName')} · ${l.s('leaveType')}',
                          subtitle: '${fmtDate(l.s('fromDate'))} - ${fmtDate(l.s('toDate'))} (${l.i('days')} day${l.i('days') == 1 ? '' : 's'}) · ${Store.branchName(l.s('branchId'))}',
                          trailing: leaveStatusLabels[Store.leaveStatus(l)],
                          onTap: () => _sheet(l, d),
                        ),
                    ]),
            ),
          ]),
        );
      },
    );
  }
}
