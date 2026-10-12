import 'package:flutter/material.dart';

import '../session.dart';
import '../widgets/offline_banner.dart';
import '../theme.dart';
import 'account.dart';
import 'checkin.dart';
import 'home.dart';
import 'insights.dart';
import 'mobilize.dart';
import 'people.dart';

/// Bottom bar: Home · People · (+) · Insights · Account.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;
  // Bumped after a check-in/mobilization so tabs reload their numbers.
  int _refresh = 0;

  Future<void> _startAction() async {
    final me = session.me!;
    final canCheckin = me.canOperate && me.moduleEvents;
    final canMobilize = me.canOperate && me.moduleMobilization;
    String? choice;
    if (canCheckin && canMobilize) {
      choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _ActionTile(
                  icon: Icons.how_to_reg,
                  color: AppColors.teal,
                  title: 'Check in',
                  subtitle: 'Mark voters present at an event',
                  onTap: () => Navigator.pop(ctx, 'checkin')),
              const SizedBox(height: 10),
              _ActionTile(
                  icon: Icons.campaign,
                  color: AppColors.amber,
                  title: 'Mobilize',
                  subtitle: 'Register voters during outreach',
                  onTap: () => Navigator.pop(ctx, 'mobilize')),
            ]),
          ),
        ),
      );
    } else if (canCheckin) {
      choice = 'checkin';
    } else if (canMobilize) {
      choice = 'mobilize';
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Your role is read-only. Ask an admin for field access.')));
      return;
    }
    if (choice == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => choice == 'checkin' ? const CheckinFlow() : const MobilizeFlow(),
    ));
    if (mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(key: ValueKey('home$_refresh'), onStart: _startAction),
      PeopleScreen(key: ValueKey('people$_refresh')),
      InsightsScreen(key: ValueKey('insights$_refresh')),
      const AccountScreen(),
    ];
    return Scaffold(
      body: Column(children: [
        const SafeArea(bottom: false, child: OfflineBanner()),
        Expanded(child: IndexedStack(index: _tab, children: pages)),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _startAction,
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        tooltip: 'Check in or mobilize',
        child: const Icon(Icons.add, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        height: 64,
        padding: EdgeInsets.zero,
        child: Row(children: [
          _navItem(0, Icons.home_outlined, Icons.home, 'Home'),
          _navItem(1, Icons.people_outline, Icons.people, 'People'),
          const SizedBox(width: 72),
          _navItem(2, Icons.insights_outlined, Icons.insights, 'Insights'),
          _navItem(3, Icons.person_outline, Icons.person, 'Account'),
        ]),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final on = _tab == index;
    final color = on ? AppColors.teal : AppColors.muted;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tab = index),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(on ? activeIcon : icon, color: color),
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: on ? FontWeight.w700 : FontWeight.w500)),
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          leading: CircleAvatar(backgroundColor: color, foregroundColor: Colors.white, child: Icon(icon)),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: Icon(Icons.chevron_right, color: color),
          onTap: onTap,
        ),
      );
}
