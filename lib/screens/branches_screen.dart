import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/db.dart';
import '../core/perms.dart';
import '../core/store.dart';
import '../ui.dart';
import '../widgets.dart';
import 'record_form.dart';

const _branchFields = [
  FieldSpec('name', 'Branch / home name', required: true),
  FieldSpec('kind', 'Type of service', type: FT.choice, options: branchKinds, required: true),
  FieldSpec('address', 'Address', type: FT.multi),
  FieldSpec('phone', 'Phone', type: FT.phone),
  FieldSpec('manager', 'Manager (name)'),
];

/// Branches (homes and service locations). Only the Super Admin creates them.
class BranchesScreen extends StatelessWidget {
  const BranchesScreen({super.key});

  void _edit(BuildContext context, [Rec? ex]) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RecordFormScreen(
            title: ex == null ? 'Add branch' : 'Edit branch',
            fields: _branchFields,
            initial: ex?.data ?? const {},
            onSave: (d) async {
              await Store.save(tBranch, id: ex?.id, data: d, summary: 'Branch ${d['name']}');
              await Store.loadBranchNames();
            },
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final admin = AppState.instance.isAdmin;
    return SkyScaffold(
      appBar: AppBar(title: const Text('Branches')),
      floatingActionButton: admin ? FloatingActionButton(tooltip: 'Add branch', onPressed: () => _edit(context), child: const Icon(Icons.add_business_outlined)) : null,
      body: Live<List<Rec>>(
        load: Store.branches,
        builder: (c, list) => list.isEmpty
            ? EmptyState(Icons.apartment_outlined, admin ? 'No branches yet.\nTap + to add your first home or care centre.' : 'No branches yet. The administrator creates them.')
            : ListView(padding: const EdgeInsets.only(top: 8, bottom: 90), children: [
                for (final b in list)
                  InfoRow(
                    icon: b.s('kind') == 'Children Home' ? Icons.child_care : (b.s('kind') == 'Old Age Home' ? Icons.elderly : Icons.apartment),
                    color: accentViolet,
                    title: b.s('name'),
                    subtitle: '${b.s('kind')}${b.s('address').isEmpty ? '' : ' · ${b.s('address')}'}${b.s('manager').isEmpty ? '' : '\nManager: ${b.s('manager')}'}',
                    onTap: admin ? () => _edit(context, b) : null,
                  ),
              ]),
      ),
    );
  }
}

bool get canManageBranches => Perms.manageUsers;
