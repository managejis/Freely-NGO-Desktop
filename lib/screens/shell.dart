import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/perms.dart';
import '../core/users.dart';
import '../ui.dart';
import '../widgets.dart';
import 'announcements_screen.dart';
import 'attendance_screen.dart';
import 'auth_screens.dart';
import 'backup_screen.dart';
import 'beneficiaries_screen.dart';
import 'branches_screen.dart';
import 'donations_screen.dart';
import 'expenses_screen.dart';
import 'home_screen.dart';
import 'info_screens.dart';
import 'inventory_screen.dart';
import 'leave_screen.dart';
import 'people_screen.dart';
import 'reports_screen.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';
import 'users_screen.dart';

class _Dest {
  final String key, label;
  final IconData icon;
  final Widget Function() page;
  final bool badge;
  const _Dest(this.key, this.label, this.icon, this.page, {this.badge = false});
}

/// The desktop window: a navigation sidebar and the page area.
///  * 1100 px and wider  - full sidebar with labels
///  * 720 - 1100 px      - narrow icon rail
///  * below 720 px       - the sidebar becomes a drawer opened from a top bar
/// Every page opens inside the page area (a nested navigator), so the navigation stays visible.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _nav = GlobalKey<NavigatorState>();
  final _scaffold = GlobalKey<ScaffoldState>();
  String _sel = 'home';

  List<_Dest> get _main {
    final app = AppState.instance;
    return [
      _Dest('home', 'Dashboard', Icons.dashboard_rounded, () => const DashboardPage()),
      if (Perms.beneficiaries) _Dest('ben', 'Beneficiaries', Icons.groups_rounded, () => const BeneficiariesScreen()),
      if (Perms.attendance) _Dest('att', 'Attendance', Icons.fact_check_rounded, () => const AttendanceScreen()),
      if (Perms.people) _Dest('staff', 'Staff and volunteers', Icons.badge_rounded, () => const PeopleScreen()),
      _Dest('leave', 'Leave', Icons.event_busy_rounded, () => const LeaveScreen()),
      if (Perms.donations) _Dest('don', 'Donations', Icons.volunteer_activism_rounded, () => const DonationsScreen()),
      if (Perms.expenses || Perms.enterExpenses) _Dest('exp', 'Expenses', Icons.receipt_long_rounded, () => const ExpensesScreen()),
      if (Perms.inventory) _Dest('inv', 'Inventory', Icons.inventory_2_rounded, () => const InventoryScreen()),
      if (Perms.reports) _Dest('rep', 'Reports', Icons.insights_rounded, () => const ReportsScreen()),
      _Dest('br', 'Branches', Icons.apartment_rounded, () => const BranchesScreen()),
      _Dest('news', 'Announcements', Icons.campaign_rounded, () => const AnnouncementsScreen()),
      if (app.isAdmin) _Dest('users', 'Users and approvals', Icons.manage_accounts_rounded, () => const UsersScreen(), badge: true),
    ];
  }

  List<_Dest> get _more {
    final app = AppState.instance;
    return [
      _Dest('profile', 'Profile', Icons.person_outline, () => const ProfileScreen()),
      _Dest('settings', 'Settings', Icons.settings_outlined, () => const SettingsScreen()),
      _Dest('sync', 'Synchronization', Icons.sync, () => const SyncScreen()),
      _Dest('backup', 'Backup / Restore', Icons.backup_outlined, () => const BackupScreen()),
      if (app.isAdmin) _Dest('audit', 'Audit log', Icons.history, () => const AuditScreen()),
      _Dest('privacy', 'Privacy & Security', Icons.privacy_tip_outlined, () => const PrivacyScreen()),
      _Dest('help', 'Help & Support', Icons.help_outline, () => const HelpScreen()),
      _Dest('about', 'About App', Icons.info_outline, () => const AboutScreen()),
    ];
  }

  void _open(_Dest d) {
    final scaffold = _scaffold.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) Navigator.pop(context);
    _nav.currentState?.pushAndRemoveUntil(
      PageRouteBuilder(pageBuilder: (_, __, ___) => d.page(), transitionDuration: Duration.zero, reverseTransitionDuration: Duration.zero),
      (r) => false,
    );
    setState(() => _sel = d.key);
  }

  void _logout() {
    final scaffold = _scaffold.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) Navigator.pop(context);
    logoutFlow(context);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.instance,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth;
        final expanded = w >= 1100, rail = !expanded && w >= 720, narrow = w < 720;
        final main = _main, more = _more;
        final pages = Navigator(
          key: _nav,
          onGenerateRoute: (_) => PageRouteBuilder(pageBuilder: (_, __, ___) => const DashboardPage(), transitionDuration: Duration.zero),
        );
        return Scaffold(
          key: _scaffold,
          backgroundColor: Colors.transparent,
          drawer: narrow
              ? Drawer(
                  backgroundColor: panelColor(context),
                  width: 300,
                  child: SafeArea(child: _Sidebar(expanded: true, main: main, more: more, selected: _sel, onOpen: _open, onLogout: _logout)),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (expanded || rail)
                Container(
                  width: expanded ? 268 : 84,
                  margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
                  decoration: BoxDecoration(color: panelColor(context), borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8))]),
                  child: ClipRRect(borderRadius: BorderRadius.circular(30), child: _Sidebar(expanded: expanded, main: main, more: more, selected: _sel, onOpen: _open, onLogout: _logout)),
                ),
              Expanded(
                child: Column(children: [
                  if (narrow)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                      child: Row(children: [
                        RoundIconButton(icon: Icons.menu_rounded, tooltip: 'Menu', onTap: () => _scaffold.currentState?.openDrawer()),
                        const Spacer(),
                        const BrandTitle(),
                        const Spacer(),
                        Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)), child: const ClipOval(child: OrgAvatar(size: 38))),
                      ]),
                    ),
                  Expanded(child: pages),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final bool expanded;
  final List<_Dest> main, more;
  final String selected;
  final void Function(_Dest) onOpen;
  final VoidCallback onLogout;
  const _Sidebar({required this.expanded, required this.main, required this.more, required this.selected, required this.onOpen, required this.onLogout});

  Widget _item(BuildContext context, _Dest d) {
    final sel = d.key == selected;
    Widget icon = Icon(d.icon, color: sel ? brandBlue : null, size: 24);
    if (d.badge) {
      final i = icon;
      icon = ListenableBuilder(listenable: Users.pending, builder: (_, __) => Badge(isLabelVisible: Users.pending.value > 0, label: Text('${Users.pending.value}'), child: i));
    }
    if (!expanded) {
      return Tooltip(
        message: d.label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => onOpen(d),
          child: Container(
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(color: sel ? brandBlue.withValues(alpha: 0.14) : null, borderRadius: BorderRadius.circular(18)),
            child: Center(child: icon),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: sel ? brandBlue.withValues(alpha: 0.14) : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onOpen(d),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: Text(d.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: sel ? brandBlue : null))),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final header = expanded
        ? Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 12),
            child: Row(children: [
              const OrgAvatar(size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text.rich(
                    TextSpan(children: [TextSpan(text: 'Freely ', style: TextStyle(color: Color(0xFFFF6A00))), TextSpan(text: 'NGO', style: TextStyle(color: Color(0xFF0047CC)))]),
                    style: TextStyle(fontFamily: 'Poppins', fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  Text(app.orgName, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
                ]),
              ),
            ]),
          )
        : const Padding(padding: EdgeInsets.fromLTRB(0, 20, 0, 12), child: Center(child: OrgAvatar(size: 46)));

    final footer = expanded
        ? Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Divider(height: 1),
              const SizedBox(height: 8),
              Row(children: [
                CircleAvatar(backgroundColor: brandBlue.withValues(alpha: 0.15), child: Text(app.userName.isEmpty ? '?' : app.userName[0].toUpperCase(), style: const TextStyle(color: brandBlue, fontWeight: FontWeight.w800))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.userName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(app.isAdmin ? 'Super Admin' : Perms.rolesText(app.roles), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
                  ]),
                ),
                IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: onLogout),
              ]),
            ]),
          )
        : Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: const Icon(Icons.more_horiz),
                onSelected: (k) => k == 'logout' ? onLogout() : onOpen(more.firstWhere((d) => d.key == k)),
                itemBuilder: (_) => [
                  for (final d in more) PopupMenuItem(value: d.key, child: Row(children: [Icon(d.icon, size: 20), const SizedBox(width: 12), Text(d.label)])),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 20), SizedBox(width: 12), Text('Log out')])),
                ],
              ),
            ]),
          );

    return Column(children: [
      header,
      Expanded(
        child: ListView(padding: const EdgeInsets.only(bottom: 8), children: [
          for (final d in main) _item(context, d),
          if (expanded) ...[
            const Padding(padding: EdgeInsets.fromLTRB(26, 16, 26, 6), child: Align(alignment: Alignment.centerLeft, child: Text('ACCOUNT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, color: Color(0xFF9A96BD))))),
            for (final d in more) _item(context, d),
          ],
        ]),
      ),
      footer,
    ]);
  }
}
