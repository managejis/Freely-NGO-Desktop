import 'package:flutter/material.dart';

import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../ui.dart';
import '../widgets.dart';
import 'announcements_screen.dart';
import 'beneficiaries_screen.dart';

class _All {
  final List<Rec> beneficiaries, people, announcements;
  _All(this.beneficiaries, this.people, this.announcements);
}

/// One search box across everything this person's roles may see.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  String _q = '';

  Future<_All> _load() async {
    await Store.loadBranchNames();
    return _All(Perms.beneficiaries ? await Store.beneficiaries() : [], Perms.people ? await Store.people() : [], await Store.announcements());
  }

  bool _hit(Rec r, List<String> keys) => keys.map(r.s).join(' ').toLowerCase().contains(_q);

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 6),
          child: TextField(autofocus: true, decoration: searchDecoration('Search beneficiaries, staff, announcements'), onChanged: (v) => setState(() => _q = v.trim().toLowerCase())),
        ),
        Expanded(
          child: _q.isEmpty
              ? const EmptyState(Icons.search, 'Type a name, ID, phone number or announcement.')
              : Live<_All>(
                  load: _load,
                  builder: (c, d) {
                    final b = d.beneficiaries.where((x) => _hit(x, ['name', 'bid', 'phone', 'guardianPhone', 'guardianName'])).toList();
                    final p = d.people.where((x) => _hit(x, ['name', 'phone', 'designation'])).toList();
                    final a = d.announcements.where((x) => _hit(x, ['title', 'body'])).toList();
                    if (b.isEmpty && p.isEmpty && a.isEmpty) return const EmptyState(Icons.search_off, 'Nothing found.');
                    return ListView(padding: const EdgeInsets.only(bottom: 30), children: [
                      if (b.isNotEmpty) const SectionTitle('Beneficiaries'),
                      for (final x in b) BeneficiaryRow(b: x, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BeneficiaryDetailScreen(id: x.id)))),
                      if (p.isNotEmpty) const SectionTitle('Staff and volunteers'),
                      for (final x in p)
                        RowCard(child: ListTile(leading: CircleAvatar(child: Text(x.s('name').isEmpty ? '?' : x.s('name')[0].toUpperCase())), title: Text(x.s('name')), subtitle: Text('${x.s('kind')} · ${x.s('designation')}'))),
                      if (a.isNotEmpty) const SectionTitle('Announcements'),
                      for (final x in a)
                        RowCard(
                          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementsScreen())),
                          child: ListTile(leading: const Icon(Icons.campaign_outlined), title: Text(x.s('title')), subtitle: Text(x.s('body'), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ),
                    ]);
                  },
                ),
        ),
      ]),
    );
  }
}
