import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/client.dart';
import '../../api/ops_api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'ops_widgets.dart';
import 'station_record.dart';

/// My stations: filter chips + search; the table becomes stacked cards.
class OpsStationsScreen extends StatefulWidget {
  final VoidCallback onChanged;
  const OpsStationsScreen({super.key, required this.onChanged});
  @override
  State<OpsStationsScreen> createState() => _OpsStationsScreenState();
}

class _OpsStationsScreenState extends State<OpsStationsScreen> {
  List<OpsStation>? _items;
  Map<String, int> _counts = {};
  String? _status;
  Object? _error;
  final _search = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final (items, counts) = await opsApi.stations(status: _status, q: _search.text.trim());
      if (mounted) {
        setState(() {
          _items = items;
          _counts = counts;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final err = _error;
    if (err is ApiException && err.code == 'no_active_election') {
      return SafeArea(child: NoActiveElection(onRetry: _load));
    }
    const chips = [
      ('issue', 'Issue'),
      ('open', 'Open'),
      ('reporting', 'Reporting'),
      ('closed', 'Closed'),
      ('uncovered', 'Uncovered')
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('My stations', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            decoration:
                const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search stations…', isDense: true),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (key, label) in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('$label ${_counts[key] ?? 0}'),
                      selected: _status == key,
                      onSelected: (on) {
                        setState(() => _status = on ? key : null);
                        _load();
                      },
                    ),
                  ),
              ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: err != null
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    Notice(errorText(err), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
                  ])
                : _items == null
                    ? const Center(child: CircularProgressIndicator())
                    : _items!.isEmpty
                        ? ListView(children: const [EmptyNote('No stations match.')])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _items!.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) => _StationCard(
                              _items![i],
                              onTap: () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => StationRecordScreen(code: _items![i].code)));
                                _load();
                                widget.onChanged();
                              },
                            ),
                          ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text('Tap a card for the full record', style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ),
      ]),
    );
  }
}

class _StationCard extends StatelessWidget {
  final OpsStation s;
  final VoidCallback onTap;
  const _StationCard(this.s, {required this.onTap});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                Text(s.turnout == null ? '—' : fmtPct(s.turnout!),
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.teal)),
              ]),
              Text('${s.code} · ${fmtNum(s.registered)} voters · ${s.ward}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                StatusPill(s.status),
                CoveragePill(s.agents),
                if (s.lastIncident != null)
                  Pill(s.lastIncident!.toUpperCase(), fg: AppColors.red, bg: AppColors.redSoft),
              ]),
            ]),
          ),
        ),
      );
}
