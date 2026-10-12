import 'package:flutter/material.dart';

import '../../session.dart';
import '../../widgets/offline_banner.dart';
import '../../theme.dart';
import '../account.dart';
import 'ops_agents.dart';
import 'ops_home.dart';
import 'ops_stations.dart';

/// Election Ops field app: Home · Stations · Agents · Account (agents get no Agents tab).
class OpsShell extends StatefulWidget {
  const OpsShell({super.key});
  @override
  State<OpsShell> createState() => _OpsShellState();
}

class _OpsShellState extends State<OpsShell> {
  int _tab = 0;
  int _refresh = 0;

  void _changed() => setState(() => _refresh++);

  @override
  Widget build(BuildContext context) {
    final isAgent = session.me!.isAgent;
    final pages = <Widget>[
      OpsHomeScreen(
          key: ValueKey('home$_refresh'), onChanged: _changed, onOpenStations: () => setState(() => _tab = 1)),
      OpsStationsScreen(key: ValueKey('stations$_refresh'), onChanged: _changed),
      if (!isAgent) const OpsAgentsScreen(),
      const AccountScreen(),
    ];
    final items = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.flag_outlined), selectedIcon: Icon(Icons.flag), label: 'Stations'),
      if (!isAgent)
        const NavigationDestination(
            icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Agents'),
      const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
    ];
    final tab = _tab.clamp(0, pages.length - 1);
    return Scaffold(
      body: Column(children: [
        const SafeArea(bottom: false, child: OfflineBanner()),
        Expanded(child: IndexedStack(index: tab, children: pages)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        backgroundColor: Colors.white,
        indicatorColor: AppColors.tealSoft,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: items,
      ),
    );
  }
}
