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

const _expenseFields = [
  FieldSpec('date', 'Expense date', type: FT.date, required: true),
  FieldSpec('category', 'Category', type: FT.choice, options: expenseCategories, required: true),
  FieldSpec('description', 'Description', required: true),
  FieldSpec('amount', 'Amount', type: FT.number, required: true),
  FieldSpec('mode', 'Payment mode', type: FT.choice, options: paymentModes),
  FieldSpec('paidTo', 'Paid to'),
  FieldSpec('branchId', 'Branch', type: FT.branch, required: true),
  FieldSpec('remarks', 'Remarks', type: FT.multi),
];

Color _statusColor(String s) => switch (s) { 'entered' => accentOrange, 'verified' => accentSky, 'approved' => accentViolet, 'paid' => accentGreen, _ => _red };

/// Expense workflow: staff enter -> manager verifies -> administrator approves -> accountant records payment.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _filter = 'all';

  void _edit([Rec? ex]) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            title: ex == null ? 'Enter expense' : 'Edit expense',
            fields: _expenseFields,
            initial: ex?.data ?? {'date': dateStr(today()), 'mode': 'Cash', 'status': 'entered', 'enteredBy': AppState.instance.mobile},
            onSave: (d) async {
              if (((d['amount'] ?? 0) as num) <= 0) throw 'Enter an amount greater than zero';
              await Store.save(tExpense, id: ex?.id, data: d, summary: 'Expense ${money((d['amount'] as num))} ${d['category']}');
            },
          ),
        ),
      );

  Future<void> _step(Rec e, String to, String question) async {
    if (!await confirm(context, question, '${e.s('category')} · ${money(amountOf(e))} · ${e.s('description')}', yes: expenseStatusLabels[to] ?? 'Yes')) return;
    await Store.advanceExpense(e, to);
  }

  void _sheet(Rec e) {
    final st = Store.expenseStatus(e);
    final v = Store.isVoid(e);
    final mine = e.s('enteredBy') == AppState.instance.mobile;
    String who(String k) => e.s(k).isEmpty ? '' : '\n$k: ${e.s(k)} (${fmtDateTime(e.s('${k}At'))})';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${money(amountOf(e))} · ${e.s('category')}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Chip(label: Text(expenseStatusLabels[st] ?? st), backgroundColor: _statusColor(st).withValues(alpha: 0.25)),
            Text('${e.s('description')}\n${fmtDate(e.s('date'))} · ${e.s('mode')}${e.s('paidTo').isEmpty ? '' : ' · to ${e.s('paidTo')}'} · ${Store.branchName(e.s('branchId'))}'
                '${e.s('remarks').isEmpty ? '' : '\n${e.s('remarks')}'}\nEntered by: ${e.s('enteredBy')}${who('verifiedBy')}${who('approvedBy')}${who('paidBy')}${who('rejectedBy')}'),
            if (v) Padding(padding: const EdgeInsets.only(top: 8), child: Text('VOID: ${e.s('voidReason')}', style: const TextStyle(color: _red, fontWeight: FontWeight.w700))),
            if (e.conflict != null) ConflictBanner(rec: e),
            const SizedBox(height: 12),
            if (!v)
              Wrap(spacing: 10, runSpacing: 8, children: [
                if (st == 'entered' && (mine || Perms.verifyExpense)) OutlinedButton.icon(icon: const Icon(Icons.edit_outlined), label: const Text('Edit'), onPressed: () { Navigator.pop(c); _edit(e); }),
                if (st == 'entered' && Perms.verifyExpense) FilledButton.icon(icon: const Icon(Icons.fact_check_outlined), label: const Text('Verify'), onPressed: () { Navigator.pop(c); _step(e, 'verified', 'Verify this expense?'); }),
                if (st == 'verified' && Perms.approveExpense) FilledButton.icon(icon: const Icon(Icons.thumb_up_alt_outlined), label: const Text('Approve'), onPressed: () { Navigator.pop(c); _step(e, 'approved', 'Approve this expense?'); }),
                if (st == 'approved' && Perms.payExpense) FilledButton.icon(icon: const Icon(Icons.payments_outlined), label: const Text('Mark as paid'), onPressed: () { Navigator.pop(c); _step(e, 'paid', 'Record payment of this expense?'); }),
                if ((st == 'entered' && Perms.verifyExpense) || (st == 'verified' && (Perms.verifyExpense || Perms.approveExpense)) || (st == 'approved' && Perms.approveExpense))
                  OutlinedButton.icon(style: OutlinedButton.styleFrom(foregroundColor: _red), icon: const Icon(Icons.close), label: const Text('Reject'), onPressed: () { Navigator.pop(c); _step(e, 'rejected', 'Reject this expense?'); }),
                if ((st == 'approved' || st == 'paid') && (Perms.approveExpense || Perms.payExpense))
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: _red),
                    icon: const Icon(Icons.block),
                    label: const Text('Void'),
                    onPressed: () async {
                      Navigator.pop(c);
                      final why = await askText(context, 'Reason for voiding', hint: 'e.g. wrong amount');
                      if (why == null || why.trim().isEmpty) return;
                      await Store.voidRec(e, why.trim(), 'expense');
                    },
                  ),
              ]),
          ]),
        ),
      ),
    );
  }

  Future<List<Rec>> _load() async {
    await Store.loadBranchNames();
    return Store.expenses();
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Expenses')),
      floatingActionButton: Perms.enterExpenses ? FloatingActionButton(tooltip: 'Enter expense', onPressed: () => _edit(), child: const Icon(Icons.add)) : null,
      body: Column(children: [
        SizedBox(
          height: 54,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(10, 10, 10, 0), children: [
            for (final f in ['all', ...expenseFlow, 'rejected'])
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(f == 'all' ? 'All' : expenseStatusLabels[f]!), selected: _filter == f, onSelected: (_) => setState(() => _filter = f))),
          ]),
        ),
        Expanded(
          child: Live<List<Rec>>(
            load: _load,
            builder: (c, all) {
              final list = all.where((e) => _filter == 'all' || Store.expenseStatus(e) == _filter).toList();
              if (list.isEmpty) return EmptyState(Icons.receipt_long_outlined, all.isEmpty ? 'No expenses yet.${Perms.enterExpenses ? '\nTap + to enter one.' : ''}' : 'No expense with this status.');
              return ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                for (final e in list)
                  InfoRow(
                    icon: Icons.receipt_long_outlined,
                    color: _statusColor(Store.expenseStatus(e)),
                    title: '${e.s('category')} · ${e.s('description')}',
                    subtitle: '${fmtDate(e.s('date'))} · ${expenseStatusLabels[Store.expenseStatus(e)]} · ${Store.branchName(e.s('branchId'))}',
                    trailing: money(amountOf(e)),
                    strike: Store.isVoid(e),
                    onTap: () => _sheet(e),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}
