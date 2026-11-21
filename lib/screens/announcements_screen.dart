import 'package:flutter/material.dart';
import '../core/desk.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../core/util.dart';
import '../ui.dart';
import '../widgets.dart';
import 'sync_screen.dart';

class AnnouncementsScreen extends StatelessWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: Perms.editAnnouncements ? FloatingActionButton(tooltip: 'Post announcement', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementEditScreen())), child: const Icon(Icons.campaign_outlined)) : null,
      body: Live<List<Rec>>(
        load: Store.announcements,
        builder: (c, list) => list.isEmpty
            ? const EmptyState(Icons.campaign_outlined, 'No announcements yet.')
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 90),
                itemCount: list.length,
                itemBuilder: (c, i) {
                  final a = list[i];
                  final urgent = a.data['urgent'] == true;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: urgent ? const Color(0xFFFFCDD2) : (isDark(context) ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.white),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: softShadow(context),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (a.conflict != null) ConflictBanner(rec: a),
                        Row(children: [
                          if (urgent) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.priority_high, color: Colors.red, size: 20)),
                          Expanded(child: Text(a.s('title'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: urgent ? Colors.black87 : null))),
                          IconButton(
                            tooltip: 'Copy to share (WhatsApp, SMS, e-mail ...)',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.copy_outlined, color: urgent ? Colors.black87 : null),
                            onPressed: () => Desk.copyText(context, '${AppState.instance.orgName}\n${a.s('title')}\n\n${a.s('body')}'),
                          ),
                          if (Perms.editAnnouncements)
                            PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'edit') {
                                  Navigator.push(context, MaterialPageRoute(builder: (_) => AnnouncementEditScreen(existing: a)));
                                } else if (await confirm(context, 'Delete this announcement?', a.s('title'), yes: 'Delete')) {
                                  await Store.remove(a, 'Announcement ${a.s('title')}');
                                }
                              },
                              itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))],
                            ),
                        ]),
                        Text(fmtDate(a.s('date')), style: TextStyle(fontSize: 12, color: urgent ? Colors.black54 : Theme.of(context).colorScheme.outline)),
                        const SizedBox(height: 6),
                        Text(a.s('body'), style: TextStyle(color: urgent ? Colors.black87 : null)),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class AnnouncementEditScreen extends StatefulWidget {
  final Rec? existing;
  const AnnouncementEditScreen({super.key, this.existing});
  @override
  State<AnnouncementEditScreen> createState() => _AnnouncementEditScreenState();
}

class _AnnouncementEditScreenState extends State<AnnouncementEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.s('title'));
  late final _body = TextEditingController(text: widget.existing?.s('body'));
  late bool _urgent = widget.existing?.data['urgent'] == true;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    await Store.save(tAnnouncement, id: widget.existing?.id, summary: 'Announcement ${_title.text.trim()}', data: {
      'title': _title.text.trim(), 'body': _body.text.trim(), 'date': widget.existing?.s('date').isNotEmpty == true ? widget.existing!.s('date') : dateStr(today()), 'urgent': _urgent,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return SkyScaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Post announcement' : 'Edit announcement')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: _title, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Title *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _body, maxLines: 6, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Message *'), validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Emergency / urgent'), subtitle: const Text('Shown in red at the top of every dashboard'), value: _urgent, onChanged: (v) => setState(() => _urgent = v)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('Post')),
        ]),
      ),
    );
  }
}
