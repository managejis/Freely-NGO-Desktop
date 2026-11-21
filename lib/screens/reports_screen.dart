import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/export.dart';
import '../core/reports.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final list = allReports.where((r) => r.allowed()).toList();
    return SkyScaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: list.isEmpty
          ? const EmptyState(Icons.insights_outlined, 'No reports are available for your role.')
          : ListView(padding: const EdgeInsets.only(top: 8, bottom: 30), children: [
              for (final r in list)
                RowCard(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReportViewScreen(def: r))),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: brandBlue.withValues(alpha: 0.12), child: Icon(r.icon, color: brandBlue)),
                    title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
            ]),
    );
  }
}

class ReportViewScreen extends StatefulWidget {
  final ReportDef def;
  const ReportViewScreen({super.key, required this.def});
  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  late DateTimeRange _range = DateTimeRange(start: DateTime(today().year, today().month, 1), end: today());
  String _branch = '';
  List<Rec> _branches = [];
  ReportTable? _table;
  bool _busy = false;

  String get _subtitle => '${widget.def.dated ? '${fmtDate(dateStr(_range.start))} to ${fmtDate(dateStr(_range.end))}' : 'As on ${fmtDate(dateStr(today()))}'} · ${_branch.isEmpty ? 'All branches' : Store.branchName(_branch)}';

  @override
  void initState() {
    super.initState();
    _branch = AppState.instance.branch;
    Store.branches().then((b) async {
      _branches = b;
      await Store.loadBranchNames();
      _run();
    });
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      final t = await widget.def.build(widget.def.dated ? _range : null, _branch);
      if (mounted) setState(() => _table = t);
    } catch (e) {
      if (mounted) toast(context, 'Could not build the report: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export(bool pdf) async {
    final t = _table;
    if (t == null) return;
    setState(() => _busy = true);
    try {
      final path = await (pdf ? Exporter.pdf(t, _subtitle) : Exporter.excel(t, _subtitle));
      if (path != null && mounted) toast(context, 'Saved to $path');
    } catch (e) {
      if (mounted) toast(context, 'Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _table;
    return SkyScaffold(
      appBar: AppBar(title: Text(widget.def.title)),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (widget.def.dated)
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text('${fmtDate(dateStr(_range.start))} - ${fmtDate(dateStr(_range.end))}'),
                onPressed: () async {
                  final r = await showDateRangePicker(context: context, firstDate: DateTime(2015), lastDate: DateTime(2100), initialDateRange: _range);
                  if (r != null) { _range = r; _run(); }
                },
              ),
            if (AppState.instance.branch.isEmpty && _branches.isNotEmpty)
              PopupMenuButton<String>(
                onSelected: (v) { _branch = v; _run(); },
                itemBuilder: (_) => [const PopupMenuItem(value: '', child: Text('All branches')), for (final b in _branches) PopupMenuItem(value: b.id, child: Text(b.s('name')))],
                child: Chip(avatar: const Icon(Icons.apartment, size: 18), label: Text(_branch.isEmpty ? 'All branches' : Store.branchName(_branch))),
              ),
            if (t != null) ...[
              ActionChip(avatar: const Icon(Icons.table_chart_outlined, size: 18), label: const Text('Excel'), onPressed: _busy ? null : () => _export(false)),
              ActionChip(avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18), label: const Text('PDF'), onPressed: _busy ? null : () => _export(true)),
            ],
          ]),
        ),
        Expanded(
          child: t == null
              ? const SizedBox.shrink()
              : t.rows.isEmpty
                  ? EmptyState(Icons.inbox_outlined, 'Nothing to report for this selection.\n${t.footer.join(' · ')}')
                  : SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.all(14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          DataTable(
                            headingRowHeight: 40,
                            dataRowMinHeight: 36,
                            dataRowMaxHeight: 64,
                            columnSpacing: 20,
                            headingTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                            dataTextStyle: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurface),
                            columns: [for (final h in t.headers) DataColumn(label: Text(h))],
                            rows: [for (final r in t.rows) DataRow(cells: [for (final v in r) DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240), child: Text(v, maxLines: 3, overflow: TextOverflow.ellipsis)))])],
                          ),
                          const SizedBox(height: 10),
                          for (final f in t.footer) Text(f, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 60),
                        ]),
                      ),
                    ),
        ),
      ]),
    );
  }
}
