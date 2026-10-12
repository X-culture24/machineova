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
      floatingActionButton: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          gradient: brandGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: AppColors.purple.withValues(alpha: .4), blurRadius: 16, offset: const Offset(0, 6))
          ],
        ),
        child: FloatingActionButton(
          key: const Key('start-action'),
          onPressed: _startAction,
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          highlightElevation: 0,
          shape: const CircleBorder(),
          tooltip: 'Check in or mobilize',
          child: const Icon(Icons.add, size: 30),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 12,
        shadowColor: AppColors.purple.withValues(alpha: .2),
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        height: 68,
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
    final color = on ? AppColors.purple : AppColors.muted;
    return Expanded(
      child: InkWell(
        key: Key('tab-$label'),
        onTap: () => setState(() => _tab = index),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
            decoration: BoxDecoration(
                color: on ? AppColors.purpleSoft : Colors.transparent, borderRadius: BorderRadius.circular(99)),
            child: Icon(on ? activeIcon : icon, color: color),
          ),
          const SizedBox(height: 2),
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
