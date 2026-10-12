import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/ops_api.dart';
import '../../session.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'ops_widgets.dart';
import 'station_record.dart';

/// Manager home: scoped KPIs (2-up) and the "needs attention" list.
class OpsHomeScreen extends StatefulWidget {
  final VoidCallback onChanged;
  final VoidCallback onOpenStations;
  const OpsHomeScreen({super.key, required this.onChanged, required this.onOpenStations});
  @override
  State<OpsHomeScreen> createState() => _OpsHomeScreenState();
}

class _OpsHomeScreenState extends State<OpsHomeScreen> {
  OpsOverview? _data;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await opsApi.overview();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _open(AttentionItem a) async {
    final initial = switch (a.kind) { 'uncovered' => QuickAction.assign, 'verify' => QuickAction.results, _ => null };
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StationRecordScreen(code: a.code, initialAction: initial)));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final me = session.me!;
    final err = _error;
    if (err is ApiException && err.code == 'no_active_election') {
      return SafeArea(child: NoActiveElection(onRetry: _load));
    }
    final d = _data;
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 24), children: [
          Text('${me.scopeLabel.isEmpty ? '' : '${roleTitle(me.role)} · '}${me.scopeLabel}',
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
          Text(d?.electionName ?? 'Election day', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          if (d != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 14),
              child: Text('Scoped to ${d.scopeLabel} — ${d.stations} stations, nothing else.',
                  style: const TextStyle(color: AppColors.muted, fontSize: 13)),
            ),
          if (err != null) Notice(errorText(err), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
          if (d == null && err == null)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
          if (d != null) ...[
            KpiGrid([
              KpiTile(
                  label: 'Reporting',
                  value: fmtPct(d.stations == 0 ? 0 : d.reported / d.stations),
                  caption: '${d.reported} of ${d.stations}'),
              KpiTile(label: 'Open', value: fmtNum(d.open), caption: '${d.closed} closed'),
              KpiTile(
                  label: 'Turnout', value: fmtPct(d.turnout), caption: '${fmtNum(d.cast)} of ${fmtNum(d.registered)}'),
              KpiTile(
                  label: 'Needs me',
                  value: fmtNum(d.attention.length),
                  accent: AppColors.amber,
                  caption: '${d.issues} issues · ${d.uncovered} uncovered'),
            ]),
            SectionCard(
              title: 'Needs attention',
              trailing: TextButton(onPressed: widget.onOpenStations, child: const Text('All stations')),
              child: d.attention.isEmpty
                  ? const EmptyNote('All clear — every station is covered and nothing is flagged.')
                  : Column(children: [
                      for (final a in d.attention)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          minVerticalPadding: 10,
                          leading: Icon(Icons.circle,
                              size: 12,
                              color: switch (a.kind) {
                                'issue' => AppColors.red,
                                'uncovered' => AppColors.amber,
                                _ => const Color(0xFF2563C9),
                              }),
                          title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(a.reason,
                              style: TextStyle(color: a.kind == 'issue' ? AppColors.red : AppColors.amber)),
                          trailing: OutlinedButton(onPressed: () => _open(a), child: Text(a.action.split(' ').first)),
                          onTap: () => _open(a),
                        ),
                    ]),
            ),
          ],
        ]),
      ),
    );
  }
}

String roleTitle(String r) =>
    const {
      'owner': 'Owner',
      'executive': 'Executive',
      'admin': 'Admin',
      'chief_agent': 'Chief Agent',
      'manager': 'Manager',
      'agent': 'Agent'
    }[r] ??
    r;
