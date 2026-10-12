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
              Text('$_greeting,', style: const TextStyle(color: AppColors.muted, fontSize: 15)),
              Text(me.name.split(' ').first, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              if (me.orgName != null) Text(me.orgName!, style: const TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              if (!me.orgActive) ...[
                const Notice('This organization is inactive. Check-ins are disabled — contact your admin.',
                    fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.block),
                const SizedBox(height: 12),
              ],
              if (snap.hasError)
                Notice(errorText(snap.error!), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off)
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else ...[
                KpiGrid([
                  KpiTile(label: 'My check-ins today', value: fmtNum(snap.data!.myCheckinsToday)),
                  KpiTile(
                      label: 'My mobilized today', value: fmtNum(snap.data!.myMobilizedToday), accent: AppColors.amber),
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
