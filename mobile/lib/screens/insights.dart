import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../terms.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'turnout.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (terms.chiefs) {
      return Scaffold(
        appBar: AppBar(title: const Text('Insights', style: TextStyle(fontWeight: FontWeight.w800))),
        body: const _CheckinInsightsTab(),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Insights', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(tabs: [Tab(text: terms.checkins), Tab(text: terms.mobilization)]),
        ),
        body: const TabBarView(children: [_CheckinInsightsTab(), _MobilizationInsightsTab()]),
      ),
    );
  }
}

class _CheckinInsightsTab extends StatefulWidget {
  const _CheckinInsightsTab();
  @override
  State<_CheckinInsightsTab> createState() => _CheckinInsightsTabState();
}

class _CheckinInsightsTabState extends State<_CheckinInsightsTab> with AutomaticKeepAliveClientMixin {
  List<EventItem>? _events;
  EventItem? _event;
  CheckinInsights? _data;
  int _version = 0; // a refresh reloads the turnout card too
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Fetched again on refresh: the totals on the tiles come from the event itself.
      final wanted = _event?.id;
      final events = await api.events();
      final event = events.where((e) => e.id == wanted).firstOrNull ?? events.firstOrNull;
      final d = event == null ? null : await api.checkinInsights(event.id);
      if (mounted && _event?.id == wanted) {
        setState(() {
          _events = events;
          _event = event;
          _data = d;
          _version++;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(_error!, _load);
    if (_events == null) return const Center(child: CircularProgressIndicator());
    if (_events!.isEmpty) return EmptyNote('No ${terms.event}s yet.');
    final d = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        GroupBanner(
          kicker: '${terms.eventLabel.toUpperCase()} · TAP TO SWITCH',
          title: _event!.name,
          subtitle: '${_event!.admission} · ${_event!.active ? 'Active' : 'Closed'}',
          color: AppColors.teal,
          soft: AppColors.tealSoft,
          onTap: () async {
            final e = await pickEvent(context, 'Choose event', _events!);
            if (e != null) {
              setState(() {
                _event = e;
                _data = null;
              });
              _load();
            }
          },
        ),
        const SizedBox(height: 12),
        if (d == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          KpiGrid([
            KpiTile(label: 'Check-ins', value: fmtNum(_event!.checkins), caption: 'all visits, every day'),
            KpiTile(label: terms.uniquePeople, value: fmtNum(_event!.unique), caption: 'different people'),
            KpiTile(
                label: 'Out of region',
                value: fmtNum(_event!.outOfRegion),
                caption: _event!.checkins == 0 ? null : '${fmtPct(_event!.outOfRegion / _event!.checkins)} of check-ins',
                accent: AppColors.amber),
            KpiTile(
                label: 'Peak hour',
                value: d.peakHour == null ? '—' : hourLabel(d.peakHour!),
                caption: 'on ${d.day}',
                accent: AppColors.amber),
          ]),
          const SizedBox(height: 2),
          TurnoutCard(key: ValueKey('turnout-${_event!.id}-$_version'), event: _event!),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Check-ins by hour · ${d.day}',
            child: MiniBarChart(
              data: [for (final h in d.byHour) MapEntry(hourLabel(h.key), h.value)],
              highlight: d.byHour.indexWhere((h) => h.key == d.peakHour),
            ),
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'Attendance breakdown',
            child: Column(children: [
              _line(terms.uniquePeople, fmtNum(_event!.unique)),
              _line('Repeat check-ins', fmtNum((_event!.checkins - _event!.unique).clamp(0, _event!.checkins))),
              _line('In-region check-ins', fmtNum(_event!.checkins - _event!.outOfRegion)),
              _line('Out-of-region check-ins', fmtNum(_event!.outOfRegion)),
              const Divider(height: 20),
              d.total == 0
                ? const EmptyNote('No check-ins on this day yet.')
                : Column(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 12,
                        child: Row(children: [
                          if (d.female > 0) Expanded(flex: d.female, child: Container(color: AppColors.teal)),
                          if (d.male > 0) Expanded(flex: d.male, child: Container(color: AppColors.amber)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Female ${fmtNum(d.female)} (${fmtPct(d.female / d.total)})'),
                      Text('Male ${fmtNum(d.male)} (${fmtPct(d.male / d.total)})'),
                    ]),
                  ]),
            ]),
          ),
        ],
      ]),
    );
  }
}

Widget _line(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
    );

class _MobilizationInsightsTab extends StatefulWidget {
  const _MobilizationInsightsTab();
  @override
  State<_MobilizationInsightsTab> createState() => _MobilizationInsightsTabState();
}

class _MobilizationInsightsTabState extends State<_MobilizationInsightsTab> with AutomaticKeepAliveClientMixin {
  List<Drive>? _drives;
  Drive? _drive;
  MobilizationInsights? _data;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _drives ??= await api.drives();
      _drive ??= _drives!.isEmpty ? null : _drives!.first;
      final d = _drive == null ? null : await api.mobilizationInsights(_drive!.id);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  static const _paceLabels = {
    'ahead': 'Ahead of target',
    'on_track': 'On track',
    'behind': 'Behind pace',
    'reached': 'Target reached',
  };

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null) return _ErrorView(_error!, _load);
    if (_drives == null) return const Center(child: CircularProgressIndicator());
    if (_drives!.isEmpty) return EmptyNote(terms.chiefs ? 'No counties set up for onboarding yet.' : 'No mobilization drives yet.');
    final m = _data;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        GroupBanner(
          kicker: 'DRIVE · TAP TO SWITCH',
          title: _drive!.name,
          subtitle: m?.paceStatus == null ? '' : _paceLabels[m!.paceStatus] ?? '',
          color: AppColors.amber,
          soft: AppColors.amberSoft,
          onTap: () async {
            final d = await pickFrom<Drive>(context, 'Choose drive', _drives!, (d) => d.name, (d) => d.area);
            if (d != null) {
              setState(() {
                _drive = d;
                _data = null;
              });
              _load();
            }
          },
        ),
        const SizedBox(height: 12),
        if (m == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          KpiGrid([
            KpiTile(label: terms.peopleMobilized, value: fmtNum(m.drive.mobilized), accent: AppColors.amber),
            KpiTile(
                label: 'Of target',
                value: m.drive.target == 0 ? '—' : fmtPct(m.drive.progress),
                accent: AppColors.amber),
            KpiTile(label: 'Remaining', value: fmtNum(m.drive.remaining)),
            KpiTile(label: terms.mobilizedToday, value: fmtNum(m.today), accent: AppColors.amber),
          ]),
          SectionCard(
            title: terms.topMobilizers,
            child: m.topMobilizers.isEmpty
                ? EmptyNote(terms.nobodyMobilized)
                : Column(children: [
                    for (final (i, t) in m.topMobilizers.indexed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Avatar(t.name, color: AppColors.amber),
                        title: Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ProgressLine(t.count / m.topMobilizers.first.count),
                        ),
                        trailing:
                            Text('#${i + 1} · ${fmtNum(t.count)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
          ),
        ],
      ]),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final Future<void> Function() retry;
  const _ErrorView(this.error, this.retry);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Notice(error, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: retry, child: const Text('Try again')),
        ]),
      );
}
