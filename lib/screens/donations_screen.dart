import 'package:flutter/material.dart';
import '../core/desk.dart';

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

const _donationFields = [
  FieldSpec('date', 'Donation date', type: FT.date, required: true),
  FieldSpec('donor', 'Donor name', required: true),
  FieldSpec('donorContact', 'Donor contact', type: FT.phone),
  FieldSpec('type', 'Donation type', type: FT.choice, options: donationTypes, required: true),
  FieldSpec('amount', 'Amount (for cash / bank donations)', type: FT.number),
  FieldSpec('quantity', 'Quantity / description (for material donations)', hint: 'e.g. 50 kg rice'),
  FieldSpec('mode', 'Payment mode', type: FT.choice, options: paymentModes),
  FieldSpec('purpose', 'Purpose / restriction'),
  FieldSpec('restricted', 'Restricted donation (must be used only for the purpose above)', type: FT.yesno),
  FieldSpec('receiptNo', 'Receipt number (blank = automatic)'),
  FieldSpec('branchId', 'Branch', type: FT.branch, required: true),
  FieldSpec('remarks', 'Remarks', type: FT.multi),
];

String donationLine(Rec d) => moneyDonationTypes.contains(d.s('type')) ? money(amountOf(d)) : d.s('quantity');

class DonationsScreen extends StatefulWidget {
  const DonationsScreen({super.key});
  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  String _q = '';

  void _edit([Rec? ex]) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            title: ex == null ? 'Add donation' : 'Edit donation',
            fields: _donationFields,
            initial: ex?.data ?? {'date': dateStr(today()), 'type': 'Cash', 'mode': 'Cash'},
            onSave: (d) async {
              final money_ = moneyDonationTypes.contains(d['type']);
              final amt = ((d['amount'] ?? 0) as num).toDouble();
              if (money_ && amt <= 0) throw 'Enter the amount for a cash / bank donation';
              if (!money_ && '${d['quantity']}'.trim().isEmpty) throw 'Describe the quantity of the material donated';
              if (money_) {
                d['quantity'] = '';
              } else {
                d['amount'] = null;
              }
              if ('${d['receiptNo']}'.isEmpty) d['receiptNo'] = ex?.s('receiptNo').isNotEmpty == true ? ex!.s('receiptNo') : 'RC-${randomCode(6)}';
              await Store.save(tDonation, id: ex?.id, data: d, summary: 'Donation ${donationLine(Rec(id: '', orgId: '', type: tDonation, data: d, updatedAt: ''))} from ${d['donor']}');
            },
          ),
        ),
      );

  void _sheet(Rec d) {
    final v = Store.isVoid(d);
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${d.s('type')} · ${donationLine(d)}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('${d.s('donor')} · ${fmtDate(d.s('date'))}${d.s('donorContact').isEmpty ? '' : ' · ${d.s('donorContact')}'}'),
            Text('Receipt ${d.s('receiptNo')} · ${Store.branchName(d.s('branchId'))}'),
            if (d.s('purpose').isNotEmpty) Text('Purpose: ${d.s('purpose')}${d.data['restricted'] == true ? ' (RESTRICTED)' : ''}'),
            if (d.s('remarks').isNotEmpty) Text(d.s('remarks')),
            Text('Recorded by ${d.by} · ${fmtDateTime(d.updatedAt)}', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
            if (v) Padding(padding: const EdgeInsets.only(top: 8), child: Text('VOID: ${d.s('voidReason')}', style: const TextStyle(color: _red, fontWeight: FontWeight.w700))),
            if (d.conflict != null) ConflictBanner(rec: d),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              if (!v) OutlinedButton.icon(icon: const Icon(Icons.receipt_long_outlined), label: const Text('Copy receipt'), onPressed: () { Navigator.pop(c); shareDonationReceipt(context, d); }),
              if (!v && Perms.editDonations) OutlinedButton.icon(icon: const Icon(Icons.edit_outlined), label: const Text('Edit'), onPressed: () { Navigator.pop(c); _edit(d); }),
              if (!v && Perms.editDonations)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: _red),
                  icon: const Icon(Icons.block),
                  label: const Text('Void'),
                  onPressed: () async {
                    Navigator.pop(c);
                    final why = await askText(context, 'Reason for voiding', hint: 'e.g. entered twice');
                    if (why == null || why.trim().isEmpty) return;
                    await Store.voidRec(d, why.trim(), 'donation');
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
    return Store.donations();
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Donations')),
      floatingActionButton: Perms.editDonations ? FloatingActionButton(tooltip: 'Add donation', onPressed: () => _edit(), child: const Icon(Icons.volunteer_activism)) : null,
      body: Live<List<Rec>>(
        load: _load,
        builder: (c, all) {
          final live = all.where((d) => !Store.isVoid(d)).toList();
          final ym = dateStr(today()).substring(0, 7);
          final month = live.where((d) => d.s('date').startsWith(ym) && moneyDonationTypes.contains(d.s('type'))).fold(0.0, (a, d) => a + amountOf(d));
          final total = live.where((d) => moneyDonationTypes.contains(d.s('type'))).fold(0.0, (a, d) => a + amountOf(d));
          final list = all.where((d) => _q.isEmpty || '${d.s('donor')} ${d.s('receiptNo')} ${d.s('purpose')}'.toLowerCase().contains(_q)).toList();
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
              child: Row(children: [
                Expanded(child: _Stat2('This month', money(month), accentGreen)),
                const SizedBox(width: 10),
                Expanded(child: _Stat2('All time (cash + bank)', money(total), accentOrange)),
              ]),
            ),
            Padding(padding: const EdgeInsets.fromLTRB(14, 6, 14, 0), child: TextField(decoration: searchDecoration('Search donor, receipt or purpose'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase()))),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(Icons.volunteer_activism_outlined, all.isEmpty ? 'No donations recorded yet.' : 'Nothing matches.')
                  : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                      for (final d in list)
                        InfoRow(
                          icon: moneyDonationTypes.contains(d.s('type')) ? Icons.payments_outlined : Icons.inventory_2_outlined,
                          color: accentGreen,
                          title: d.s('donor'),
                          subtitle: '${d.s('type')} · ${fmtDate(d.s('date'))} · ${Store.branchName(d.s('branchId'))}${d.data['restricted'] == true ? '\nRestricted: ${d.s('purpose')}' : ''}',
                          trailing: donationLine(d),
                          strike: Store.isVoid(d),
                          onTap: () => _sheet(d),
                        ),
                    ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Stat2 extends StatelessWidget {
  final String label, value;
  final Color color;
  const _Stat2(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11.5)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
      );
}

void shareDonationReceipt(BuildContext context, Rec d) {
  final app = AppState.instance;
  Desk.copyText(context, '${app.orgName}\nDONATION RECEIPT\n\nReceipt no: ${d.s('receiptNo')}\nDate: ${fmtDate(d.s('date'))}\nReceived from: ${d.s('donor')}\n'
      '${moneyDonationTypes.contains(d.s('type')) ? 'Amount: Rs. ${money(amountOf(d))} (${d.s('type')}${d.s('mode').isEmpty ? '' : ', ${d.s('mode')}'})' : '${d.s('type')}: ${d.s('quantity')}'}'
      '${d.s('purpose').isEmpty ? '' : '\nPurpose: ${d.s('purpose')}'}\n\nThank you for your generous support. God bless you.');
}
