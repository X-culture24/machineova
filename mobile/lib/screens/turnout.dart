import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// The event's turnout: registered voters checked in against the registered voters of its vying
/// area, by area (constituency → ward → polling centre), and where to push next.
class TurnoutCard extends StatefulWidget {
  final EventItem event;
  const TurnoutCard({super.key, required this.event});
  @override
  State<TurnoutCard> createState() => _TurnoutCardState();
}

class _TurnoutCardState extends State<TurnoutCard> {
  Coverage? _data;
  String? _error, _constituency, _ward;
  bool _all = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final request = ++_request;
    try {
      final c = await api.coverage(widget.event.id, constituency: _constituency, ward: _ward);
      if (mounted && request == _request) setState(() => _data = c);
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = errorText(e));
    }
  }

  void _show({String? constituency, String? ward}) {
    setState(() {
      _constituency = constituency;
      _ward = ward;
      _data = null;
      _error = null;
      _all = false;
    });
    _load();
  }

  void _open(CoverageRow r) => _data!.level == 'constituency'
      ? _show(constituency: r.area)
      : _show(constituency: _constituency, ward: r.area);

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final drilled = _constituency != null || _ward != null;
    return SectionCard(
      title: 'Voter turnout · ${d?.label ?? widget.event.vyingArea}',
      trailing: drilled
          ? TextButton(
              key: const Key('turnout-up'),
              onPressed: () => _show(constituency: _ward != null ? _constituency : null),
              child: const Text('Up a level'))
          : null,
      child: _error != null
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
              const SizedBox(height: 10),
              OutlinedButton(
                  onPressed: () => _show(constituency: _constituency, ward: _ward), child: const Text('Try again')),
            ])
          : d == null
              ? const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
              : _content(d),
    );
  }

  Widget _content(Coverage d) {
    const first = 8;
    final rows = _all ? d.rows : d.rows.take(first).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      KpiGrid([
        KpiTile(
            label: 'Registered voters reached',
            value: fmtNum(d.reached),
            caption: 'of ${fmtNum(d.registered)} registered',
            accent: AppColors.teal),
        KpiTile(label: 'Turnout', value: fmtTurnout(d.reached, d.registered), accent: AppColors.teal),
        KpiTile(label: 'Remaining', value: fmtNum(d.remaining), caption: 'still to reach'),
        KpiTile(
            label: 'Not registered',
            icon: Icons.person_off_outlined,
            value: fmtNum(d.notRegistered),
            caption: 'reached, not on the register',
            accent: AppColors.amber),
      ]),
      Text(
        'Female ${fmtNum(d.female)} · Male ${fmtNum(d.male)}'
        '${d.topAgeGroup == null ? '' : ' · Top age group ${d.topAgeGroup}'}',
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
      if (d.pushHereNext.isNotEmpty) ...[
        const SizedBox(height: 10),
        Notice(
          'Push here next: ${d.pushHereNext.map((r) => '${r.area} (${fmtNum(r.remaining)} to reach)').join(' · ')}',
          fg: AppColors.amber,
          bg: AppColors.amberSoft,
          icon: Icons.flag_outlined,
        ),
      ],
      const SizedBox(height: 14),
      Text('By ${d.areaLabel.toLowerCase()}', style: const TextStyle(fontWeight: FontWeight.w700)),
      if (d.rows.isEmpty) const EmptyNote('No registered voters found for this area.'),
      for (final r in rows)
        _TurnoutRow(
          title: r.area,
          reached: r.reached,
          registered: r.registered,
          note: r.statusLabel,
          onTap: d.canDrill ? () => _open(r) : null,
        ),
      if (d.rows.length > first)
        TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show fewer' : 'Show all ${fmtNum(d.rows.length)}')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('open-stations'),
        icon: const Icon(Icons.how_to_vote_outlined),
        label: const Text('Polling-station turnout'),
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => StationTurnoutScreen(event: widget.event))),
      ),
    ]);
  }
}

class _TurnoutRow extends StatelessWidget {
  final String title;
  final String? note;
  final int reached, registered;
  final VoidCallback? onTap;
  const _TurnoutRow({required this.title, required this.reached, required this.registered, this.note, this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
                  const SizedBox(width: 8),
                  Text(fmtTurnout(reached, registered), style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 5),
                ProgressLine(registered == 0 ? 0 : reached / registered, color: AppColors.teal),
                const SizedBox(height: 4),
                Text(
                  ['${fmtNum(reached)} of ${fmtNum(registered)} registered', if (note != null) note!].join(' · '),
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.muted),
          ]),
        ),
      );
}

/// Every polling station of the event's vying area: voters checked in against registered voters.
class StationTurnoutScreen extends StatefulWidget {
  final EventItem event;
  const StationTurnoutScreen({super.key, required this.event});
  @override
  State<StationTurnoutScreen> createState() => _StationTurnoutScreenState();
}

class _StationTurnoutScreenState extends State<StationTurnoutScreen> {
  List<StationCoverage>? _all;
  List<StationCoverage> _shown = const [];
  int _reached = 0, _registered = 0, _withTurnout = 0;
  String? _error;
  String _query = '', _view = 'all'; // all | reached | zero

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await api.eventStations(widget.event.id);
      if (!mounted) return;
      setState(() {
        _all = all;
        _error = null;
        _reached = all.fold(0, (n, s) => n + s.reached);
        _registered = all.fold(0, (n, s) => n + s.registered);
        _withTurnout = all.where((s) => s.reached > 0).length;
        _filter();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = _message(e));
      }
    }
  }

  static String _message(Object e) =>
      e is ApiException ? e.message : 'No signal. Polling-station turnout needs a connection.';

  void _filter() => _shown = [
        for (final s in _all ?? const <StationCoverage>[])
          if ((_view == 'all' || (_view == 'reached') == (s.reached > 0)) && s.matches(_query)) s
      ];

  @override
  Widget build(BuildContext context) {
    final all = _all;
    return Scaffold(
      appBar: AppBar(title: const Text('Polling-station turnout')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                sliver: SliverToBoxAdapter(child: _header(all)),
              ),
              if (all != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.builder(
                    itemCount: _shown.length,
                    itemBuilder: (_, i) {
                      final s = _shown[i];
                      return _TurnoutRow(
                          title: s.name,
                          reached: s.reached,
                          registered: s.registered,
                          note: [s.ward, s.constituency].where((p) => p.isNotEmpty).join(', '));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(List<StationCoverage>? all) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${widget.event.name} · ${widget.event.vyingArea}', style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 12),
        if (_error != null) ...[
          Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ] else if (all == null)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
        else ...[
          KpiTile(
              label: 'Overall turnout',
              value: fmtTurnout(_reached, _registered),
              caption: '${fmtNum(_reached)} of ${fmtNum(_registered)} registered voters',
              accent: AppColors.teal),
          const SizedBox(height: 12),
          TextField(
            key: const Key('station-search'),
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Search station or area', isDense: true),
            onChanged: (v) => setState(() {
              _query = v;
              _filter();
            }),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final (value, label) in [
              ('all', 'All ${fmtNum(all.length)}'),
              ('reached', 'With check-ins ${fmtNum(_withTurnout)}'),
              ('zero', 'Zero ${fmtNum(all.length - _withTurnout)}'),
            ])
              ChoiceChip(
                key: Key('stations-$value'),
                label: Text(label),
                selected: _view == value,
                selectedColor: AppColors.tealSoft,
                onSelected: (_) => setState(() {
                  _view = value;
                  _filter();
                }),
              ),
          ]),
          if (_shown.isEmpty) const EmptyNote('No polling stations match.'),
        ],
      ]);
}
