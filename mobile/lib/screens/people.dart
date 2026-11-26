import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../terms.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // SDICS: one list, the members checked in (with their phone numbers).
    if (terms.chiefs) {
      return Scaffold(
        appBar: AppBar(title: Text(terms.checkins, style: const TextStyle(fontWeight: FontWeight.w800))),
        body: const _PeopleList(checkins: true),
      );
    }
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('People', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(tabs: [Tab(text: terms.checkins), Tab(text: terms.mobilized)]),
        ),
        body: const TabBarView(children: [_PeopleList(checkins: true), _PeopleList(checkins: false)]),
      ),
    );
  }
}

class _Group {
  final String id, name;
  _Group(this.id, this.name);
}

class _PeopleList extends StatefulWidget {
  final bool checkins;
  const _PeopleList({required this.checkins});
  @override
  State<_PeopleList> createState() => _PeopleListState();
}

class _PeopleListState extends State<_PeopleList> with AutomaticKeepAliveClientMixin {
  List<_Group> _groups = [];
  String? _groupId;
  String? _participants; // null (all) | selected | general
  final _search = TextEditingController();
  Timer? _debounce;
  List<PersonRecord>? _rows;
  String? _error;
  CheckinQuery _query = const CheckinQuery();
  Map<String, List<FacetValue>> _facets = const {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _load();
    _loadFacets();
  }

  Future<void> _loadFacets() async {
    if (!widget.checkins) return;
    try {
      final f = await api.checkinFacets(eventId: _groupId, participants: _participants);
      if (mounted) setState(() => _facets = f);
    } catch (_) {
      // Filters fall back to none; the list reports errors itself.
    }
  }

  static const _sorts = [
    ('at', true, 'Newest first'),
    ('at', false, 'Oldest first'),
    ('name', false, 'Name A–Z'),
    ('name', true, 'Name Z–A'),
    ('age', false, 'Youngest first'),
    ('age', true, 'Oldest (age) first'),
    ('sex', false, 'Sex'),
    ('county', false, 'County'),
    ('constituency', false, 'Constituency'),
    ('ward', false, 'Ward'),
    ('region', true, 'In region first'),
    ('event', false, 'Event'),
    ('by', false, 'Checked in by'),
  ];

  static const _filterLabels = [
    ('sex', 'Sex'),
    ('age_group', 'Age group'),
    ('county', 'County'),
    ('constituency', 'Constituency'),
    ('ward', 'Ward'),
    ('region', 'Region'),
    ('home_county', 'Home county'),
    ('by', 'Checked in by'),
  ];

  String _facetLabel(String key, FacetValue f) => switch ((key, f.value)) {
        ('sex', 'F') => 'Female',
        ('sex', 'M') => 'Male',
        ('region', 'in') => 'In region',
        ('region', 'out') => 'Out of region',
        _ => f.label,
      };

  /// Sort and demographic filters in a sheet; applied when closed with Show.
  Future<void> _openFilters() async {
    var filters = Map<String, String>.from(_query.filters);
    var sort = (_query.sort, _query.descending);
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Sort & filter', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: const Key('people-sort'),
                  initialValue: _sorts.indexWhere((x) => x.$1 == sort.$1 && x.$2 == sort.$2).clamp(0, _sorts.length - 1),
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Sort by', isDense: true),
                  items: [for (var i = 0; i < _sorts.length; i++) DropdownMenuItem(value: i, child: Text(_sorts[i].$3))],
                  onChanged: (i) => setSheet(() => sort = (_sorts[i!].$1, _sorts[i].$2)),
                ),
                for (final (key, label) in _filterLabels)
                  if ((_facets[key] ?? const []).isNotEmpty || filters[key] != null) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      key: Key('people-filter-$key'),
                      initialValue: filters[key],
                      isExpanded: true,
                      decoration: InputDecoration(labelText: label, isDense: true),
                      items: [
                        DropdownMenuItem(value: null, child: Text('All · ${label.toLowerCase()}')),
                        for (final f in _facets[key] ?? const <FacetValue>[])
                          DropdownMenuItem(
                              value: f.value,
                              child: Text('${_facetLabel(key, f)} (${fmtNum(f.count)})', overflow: TextOverflow.ellipsis)),
                        if (filters[key] != null && !(_facets[key] ?? const []).any((f) => f.value == filters[key]))
                          DropdownMenuItem(value: filters[key], child: Text(filters[key]!)),
                      ],
                      onChanged: (v) => setSheet(() => v == null ? filters.remove(key) : filters[key] = v),
                    ),
                  ],
                const SizedBox(height: 16),
                Row(children: [
                  TextButton(
                    onPressed: () => setSheet(() {
                      filters = {};
                      sort = ('at', true);
                    }),
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton(
                      key: const Key('people-filter-apply'),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Show')),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
    if (applied == true && mounted) {
      setState(() => _query = CheckinQuery(filters: filters, sort: sort.$1, descending: sort.$2));
      _load();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = widget.checkins
          ? [for (final e in await api.events()) _Group(e.id, e.name)]
          : [for (final d in await api.drives()) _Group(d.id, d.name)];
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      // The list itself reports errors; the filter just stays empty.
    }
  }

  int _request = 0; // a slow answer to an older search or filter is dropped

  Future<void> _load() async {
    final request = ++_request;
    try {
      final q = _search.text.trim();
      final rows = widget.checkins
          ? await api.checkins(eventId: _groupId, q: q, participants: _participants, query: _query)
          : await api.mobilizations(driveId: _groupId, q: q);
      if (mounted && request == _request) {
        setState(() {
          _rows = rows;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && request == _request) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final color = widget.checkins ? AppColors.teal : AppColors.amber;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _groupId,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.checkins ? terms.eventLabel : terms.driveLabel, isDense: true),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.checkins ? 'All ${terms.event}s' : (terms.chiefs ? 'All counties' : 'All drives'))),
                for (final g in _groups)
                  DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() => _groupId = v);
                _load();
                _loadFacets();
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.checkins ? 'Search name, ID or phone' : 'Search name or ID number',
                  isDense: true),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _load);
              },
            ),
          ),
          if (widget.checkins) ...[
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: !_query.isDefault,
              label: Text('${_query.filters.length + (_query.sort == 'at' && _query.descending ? 0 : 1)}'),
              child: IconButton.filledTonal(
                key: const Key('people-filters'),
                tooltip: 'Sort & filter',
                icon: const Icon(Icons.tune),
                onPressed: _openFilters,
              ),
            ),
          ],
        ]),
      ),
      if (widget.checkins)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(children: [
            for (final (value, label) in const [
              (null, 'All participants'),
              ('selected', 'Selected'),
              ('general', 'General'),
            ]) ...[
              ChoiceChip(
                key: Key('participants-${value ?? 'all'}'),
                label: Text(label),
                selected: _participants == value,
                selectedColor: AppColors.tealSoft,
                onSelected: (_) {
                  setState(() => _participants = value);
                  _load();
                  _loadFacets();
                },
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
      if (_rows != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child:
                Text('${fmtNum(_rows!.length)} people', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _error != null
              ? ListView(padding: const EdgeInsets.all(16), children: [
                  Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
                ])
              : _rows == null
                  ? const Center(child: CircularProgressIndicator())
                  : _rows!.isEmpty
                      ? ListView(children: const [EmptyNote('No one here yet.')])
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(8, 4, 8, 96),
                          itemCount: _rows!.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final p = _rows![i];
                            return ListTile(
                              leading: Avatar(p.name, color: color),
                              title: Text(p.name.isEmpty ? 'Name not on record' : p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  widget.checkins
                                      ? '${p.phone ?? 'No phone'} · ${p.ward}\n${[
                                          'ID ${maskId(p.nationalId)}',
                                          if (p.sex == 'F') 'Female' else if (p.sex == 'M') 'Male',
                                          if (p.age != null) '${p.age} yrs',
                                        ].join(' · ')}'
                                          '${p.selectedParticipant == null ? '' : p.selectedParticipant! ? ' · Selected' : ' · General'}'
                                      : 'ID ${maskId(p.nationalId)} · ${p.ward}\n${p.groupName}',
                                  maxLines: 2),
                              isThreeLine: true,
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(fmtTime(p.at), style: const TextStyle(fontSize: 12, color: AppColors.muted)),
                                  if (p.inRegion != null) ...[const SizedBox(height: 4), RegionPill(p.inRegion!)],
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ),
    ]);
  }
}
