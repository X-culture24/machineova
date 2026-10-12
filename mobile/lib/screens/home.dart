import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onStart;
  const HomeScreen({super.key, required this.onStart});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData> _future = api.home();

  Future<void> _refresh() async {
    final f = api.home();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {
      // Error is rendered by the FutureBuilder.
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final me = session.me!;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<HomeData>(
          future: _future,
          builder: (context, snap) {
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
              _Hero(greeting: _greeting, me: me, data: snap.data),
              const SizedBox(height: 16),
              if (!me.orgActive) ...[
                const Notice('This organization is inactive. Check-ins are disabled — contact your admin.',
                    fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.block),
                const SizedBox(height: 12),
              ],
              _QuickActions(onStart: widget.onStart),
              const SizedBox(height: 16),
              if (snap.hasError)
                Notice(errorText(snap.error!), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off)
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                KpiGrid([
                  KpiTile(label: 'Team check-ins today', value: fmtNum(snap.data!.orgCheckinsToday)),
                  KpiTile(
                      label: 'Team mobilized today',
                      value: fmtNum(snap.data!.orgMobilizedToday),
                      accent: AppColors.amber),
                ]),
                const SizedBox(height: 6),
                SectionCard(
                  title: 'Recent activity',
                  trailing: TextButton(onPressed: widget.onStart, child: const Text('Start')),
                  child: snap.data!.feed.isEmpty
                      ? const EmptyNote('Nothing yet today. Tap + to check in or mobilize.')
                      : Column(children: [for (final f in snap.data!.feed) _FeedRow(f)]),
                ),
              ],
            ]);
          },
        ),
      ),
    );
  }
}

class _FeedRow extends StatelessWidget {
  final FeedItem f;
  const _FeedRow(this.f);

  @override
  Widget build(BuildContext context) {
    final color = f.isCheckin ? AppColors.teal : AppColors.amber;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Avatar(f.name, color: color),
      title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('${f.isCheckin ? 'Checked in' : 'Mobilized'} · ${f.group} · ${f.by}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Text(fmtTime(f.at), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    );
  }
}


/// Gradient greeting card with the operator's own numbers for today.
class _Hero extends StatelessWidget {
  final String greeting;
  final Me me;
  final HomeData? data;
  const _Hero({required this.greeting, required this.me, required this.data});

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(16)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: brandGradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [BoxShadow(color: AppColors.purple.withValues(alpha: .3), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$greeting,', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(me.name.split(' ').first,
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
              if (me.orgName != null)
                Text(me.orgName!, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Text(initials(me.name), style: const TextStyle(color: AppColors.purple, fontWeight: FontWeight.w700)),
          ),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          stat('Checked in today', data == null ? '–' : fmtNum(data!.myCheckinsToday)),
          const SizedBox(width: 10),
          stat('Mobilized today', data == null ? '–' : fmtNum(data!.myMobilizedToday)),
        ]),
      ]),
    );
  }
}

/// The two field jobs, one tap each.
class _QuickActions extends StatelessWidget {
  final VoidCallback onStart;
  const _QuickActions({required this.onStart});

  @override
  Widget build(BuildContext context) {
    final me = session.me!;
    Widget tile(String title, String sub, IconData icon, Color color, Color soft, bool enabled) => Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: enabled ? onStart : null,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: color),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  Text(sub, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      tile('Check in', 'Mark voters present', Icons.how_to_reg, AppColors.teal, AppColors.tealSoft,
          me.canOperate && me.moduleEvents),
      const SizedBox(width: 12),
      tile('Mobilize', 'Register in the field', Icons.campaign, AppColors.amber, AppColors.amberSoft,
          me.canOperate && me.moduleMobilization),
    ]);
  }
}
