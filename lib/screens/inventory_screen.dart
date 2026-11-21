import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'record_form.dart';

const _expiredColor = Color(0xFFFFCDD2);
const _soonColor = Color(0xFFFFCC80);
const _lowColor = Color(0xFFFFF0B3);
const _expirySoonDays = 30;

const _itemFields = [
  FieldSpec('name', 'Item name', required: true),
  FieldSpec('category', 'Category', type: FT.choice, options: inventoryCategories, required: true),
  FieldSpec('unit', 'Unit (kg, packets, strips, pieces ...)', required: true),
  FieldSpec('minStock', 'Minimum stock (alert level)', type: FT.number),
  FieldSpec('expiryDate', 'Expiry date (if any)', type: FT.date),
  FieldSpec('branchId', 'Branch / store', type: FT.branch, required: true),
];

class _Inv {
  final List<Rec> items, tx;
  final Map<String, double> bal;
  _Inv(this.items, this.tx) : bal = Store.balances(tx);
}

String qtyText(double v, String unit) => '${v == v.roundToDouble() ? v.toInt() : v} $unit';

/// 0 ok, 1 low, 2 expiring soon, 3 expired
int stockAlert(Rec item, double bal) {
  final d = parseDate(item.s('expiryDate'));
  if (d != null) {
    final left = daysBetween(today(), d);
    if (left < 0) return 3;
    if (left <= _expirySoonDays) return 2;
  }
  if (bal <= Store.minStockOf(item)) return 1;
  return 0;
}

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  String _q = '';
  String? _cat;
  bool _alertsOnly = false;

  Future<_Inv> _load() async {
    await Store.loadBranchNames();
    return _Inv(await Store.items(), await Store.stockTx());
  }

  void _addItem() => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            title: 'Register item',
            fields: _itemFields,
            initial: const {},
            onSave: (d) async {
              final item = await Store.save(tItem, data: d, summary: 'Item ${d['name']}');
              await Store.save(tStock, audit: false, data: {'itemId': item.id, 'itemName': d['name'], 'branchId': d['branchId'], 'kind': 'in', 'qty': 0, 'date': dateStr(today()), 'note': 'Item registered'});
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Inventory')),
      floatingActionButton: Perms.editItems ? FloatingActionButton(tooltip: 'Register item', onPressed: _addItem, child: const Icon(Icons.add)) : null,
      body: Live<_Inv>(
        load: _load,
        builder: (c, inv) {
          final alerts = inv.items.where((i) => stockAlert(i, inv.bal[i.id] ?? 0) > 0).length;
          final list = inv.items.where((i) {
            if (_cat != null && i.s('category') != _cat) return false;
            if (_alertsOnly && stockAlert(i, inv.bal[i.id] ?? 0) == 0) return false;
            return _q.isEmpty || '${i.s('name')} ${i.s('category')}'.toLowerCase().contains(_q);
          }).toList();
          return Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(14, 14, 14, 0), child: TextField(decoration: searchDecoration('Search items'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase()))),
            SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(10, 8, 10, 0), children: [
                Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: FilterChip(label: Text('Alerts ($alerts)'), selected: _alertsOnly, onSelected: (v) => setState(() => _alertsOnly = v))),
                for (final cat in inventoryCategories) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ChoiceChip(label: Text(cat), selected: _cat == cat, onSelected: (v) => setState(() => _cat = v ? cat : null))),
              ]),
            ),
            Expanded(
              child: list.isEmpty
                  ? EmptyState(Icons.inventory_2_outlined, inv.items.isEmpty ? 'No items yet.${Perms.editItems ? '\nTap + to register one.' : ''}' : 'Nothing matches.')
                  : ListView(padding: const EdgeInsets.only(top: 6, bottom: 90), children: [
                      for (final i in list) _row(context, i, inv.bal[i.id] ?? 0),
                    ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _row(BuildContext context, Rec i, double bal) {
    final a = stockAlert(i, bal);
    final color = a == 3 ? _expiredColor : (a == 2 ? _soonColor : (a == 1 ? _lowColor : null));
    final tag = a == 3 ? 'EXPIRED' : (a == 2 ? 'EXPIRING SOON' : (a == 1 ? 'LOW STOCK' : ''));
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: color ?? cardColor(context), borderRadius: BorderRadius.circular(24), boxShadow: softShadow(context)),
      child: ListTile(
        textColor: color == null ? null : Colors.black87,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ItemDetailScreen(id: i.id))),
        title: Text(i.s('name'), style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text('${i.s('category')} · ${Store.branchName(i.s('branchId'))}${i.s('expiryDate').isEmpty ? '' : '\nExpiry ${fmtDate(i.s('expiryDate'))}'}'),
        isThreeLine: i.s('expiryDate').isNotEmpty,
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(qtyText(bal, i.s('unit')), style: const TextStyle(fontWeight: FontWeight.w800)),
          if (tag.isNotEmpty) Text(tag, style: const TextStyle(fontSize: 10.5, color: Colors.red, fontWeight: FontWeight.w800)),
        ]),
      ),
    );
  }
}

// ====================================================================== item detail: stock in / issue / adjust / transfer
class ItemDetailScreen extends StatelessWidget {
  final String id;
  const ItemDetailScreen({super.key, required this.id});

  Future<(Rec?, List<Rec>)> _load() async {
    await Store.loadBranchNames();
    final item = await Db.instance.get(id);
    final tx = (await Store.stockTx()).where((t) => t.s('itemId') == id).toList()..sort((a, b) => '${b.s('date')}${b.updatedAt}'.compareTo('${a.s('date')}${a.updatedAt}'));
    return (item, tx);
  }

  Future<void> _move(BuildContext context, Rec item, double bal, String kind) async {
    final qty = TextEditingController();
    final note = TextEditingController();
    var sign = 1;
    final title = {'in': 'Stock in', 'issue': 'Issue stock', 'adjust': 'Adjust stock'}[kind]!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (kind == 'adjust')
              SegmentedButton<int>(segments: const [ButtonSegment(value: -1, label: Text('Remove')), ButtonSegment(value: 1, label: Text('Add'))], selected: {sign}, onSelectionChanged: (v) => set(() => sign = v.first)),
            if (kind == 'adjust') const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Quantity (${item.s('unit')})')),
            const SizedBox(height: 10),
            TextField(controller: note, decoration: InputDecoration(labelText: kind == 'issue' ? 'Issued to / purpose' : (kind == 'in' ? 'Source (donation, purchase ...)' : 'Reason'))),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save'))],
        ),
      ),
    );
    final n = double.tryParse(qty.text.trim());
    if (ok != true || n == null || n <= 0) return;
    final delta = kind == 'in' ? n : (kind == 'issue' ? -n : sign * n);
    if (bal + delta < 0) {
      if (context.mounted) toast(context, 'Not enough stock: only ${qtyText(bal, item.s('unit'))} available.');
      return;
    }
    await Store.save(tStock, data: {'itemId': item.id, 'itemName': item.s('name'), 'branchId': item.s('branchId'), 'kind': kind, 'qty': r2(delta), 'date': dateStr(today()), 'note': note.text.trim()},
        summary: '${stockKinds[kind]} ${qtyText(r2(delta), item.s('unit'))} ${item.s('name')}');
  }

  /// Moves stock to another branch: stock out here, stock in on that branch's own item of the same name.
  Future<void> _transfer(BuildContext context, Rec item, double bal) async {
    final branches = (await Store.branches()).where((b) => b.id != item.s('branchId')).toList();
    if (!context.mounted) return;
    if (branches.isEmpty) return toast(context, 'There is no other branch.');
    Rec? to;
    final qty = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Transfer to another branch'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<Rec>(isExpanded: true, decoration: const InputDecoration(labelText: 'To branch'), items: [for (final b in branches) DropdownMenuItem(value: b, child: Text(b.s('name')))], onChanged: (v) => to = v),
            const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(labelText: 'Quantity (${item.s('unit')})')),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Transfer'))],
        ),
      ),
    );
    final n = double.tryParse(qty.text.trim());
    if (ok != true || to == null || n == null || n <= 0) return;
    if (n > bal) {
      if (context.mounted) toast(context, 'Not enough stock: only ${qtyText(bal, item.s('unit'))} available.');
      return;
    }
    final dest = to!;
    final existing = (await Store.items()).where((x) => x.s('branchId') == dest.id && x.s('name').toLowerCase() == item.s('name').toLowerCase()).toList();
    final target = existing.isNotEmpty
        ? existing.first
        : await Store.save(tItem, data: {...item.data, 'branchId': dest.id}, summary: 'Item ${item.s('name')} at ${dest.s('name')}');
    final note = 'Transfer ${Store.branchName(item.s('branchId'))} -> ${dest.s('name')}';
    await Store.save(tStock, audit: false, data: {'itemId': item.id, 'itemName': item.s('name'), 'branchId': item.s('branchId'), 'kind': 'out', 'qty': -n, 'date': dateStr(today()), 'note': note});
    await Store.save(tStock, data: {'itemId': target.id, 'itemName': item.s('name'), 'branchId': dest.id, 'kind': 'recv', 'qty': n, 'date': dateStr(today()), 'note': note}, summary: '$note: ${qtyText(n, item.s('unit'))} ${item.s('name')}');
  }

  @override
  Widget build(BuildContext context) {
    return Live<(Rec?, List<Rec>)>(
      load: _load,
      builder: (c, d) {
        final item = d.$1;
        if (item == null || item.deleted) return SkyScaffold(appBar: AppBar(), body: const EmptyState(Icons.inventory_2_outlined, 'This item is no longer available.'));
        final bal = Store.balances(d.$2)[item.id] ?? 0;
        final a = stockAlert(item, bal);
        return SkyScaffold(
          appBar: AppBar(title: Text(item.s('name')), actions: [
            if (Perms.editItems)
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => RecordFormScreen(title: 'Edit item', fields: _itemFields, initial: item.data, onSave: (x) => Store.save(tItem, id: item.id, data: x, summary: 'Item ${x['name']}').then((_) {})))),
              ),
          ]),
          body: ListView(padding: const EdgeInsets.only(bottom: 40), children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: a == 3 ? _expiredColor : (a == 2 ? _soonColor : (a == 1 ? _lowColor : const Color(0xFFC8E6C9))), borderRadius: BorderRadius.circular(22)),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.black87),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(qtyText(bal, item.s('unit')), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                  Text('${item.s('category')} · ${Store.branchName(item.s('branchId'))}'),
                  Text('Minimum stock: ${qtyText(Store.minStockOf(item), item.s('unit'))}'),
                  if (item.s('expiryDate').isNotEmpty) Text('Expiry: ${fmtDate(item.s('expiryDate'))}'),
                  if (a > 0) Text(a == 3 ? 'EXPIRED' : (a == 2 ? 'Expiring within $_expirySoonDays days' : 'Below the minimum stock'), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            if (Perms.stockMoves)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(icon: const Icon(Icons.add), label: const Text('Stock in'), onPressed: () => _move(context, item, bal, 'in')),
                  OutlinedButton.icon(icon: const Icon(Icons.north_east), label: const Text('Issue'), onPressed: () => _move(context, item, bal, 'issue')),
                  OutlinedButton.icon(icon: const Icon(Icons.tune), label: const Text('Adjust'), onPressed: () => _move(context, item, bal, 'adjust')),
                  if (Perms.transferStock) OutlinedButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('Transfer'), onPressed: () => _transfer(context, item, bal)),
                ]),
              ),
            SectionTitle('Stock history (${d.$2.length})'),
            for (final t in d.$2)
              ListTile(
                dense: true,
                leading: Icon(((t.data['qty'] ?? 0) as num) >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline, color: ((t.data['qty'] ?? 0) as num) >= 0 ? Colors.green : Colors.red),
                title: Text('${stockKinds[t.s('kind')] ?? t.s('kind')}: ${((t.data['qty'] ?? 0) as num) >= 0 ? '+' : ''}${qtyText(((t.data['qty'] ?? 0) as num).toDouble(), item.s('unit'))}'),
                subtitle: Text('${fmtDate(t.s('date'))} · ${t.by}${t.s('note').isEmpty ? '' : '\n${t.s('note')}'}'),
                isThreeLine: t.s('note').isNotEmpty,
              ),
          ]),
        );
      },
    );
  }
}
