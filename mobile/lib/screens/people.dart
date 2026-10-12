import 'dart:async';

import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';

class PeopleScreen extends StatelessWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('People', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(tabs: [Tab(text: 'Check-ins'), Tab(text: 'Mobilized')]),
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
  final _search = TextEditingController();
  Timer? _debounce;
  List<PersonRecord>? _rows;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
    _load();
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

  Future<void> _load() async {
    try {
      final q = _search.text.trim();
      final rows = widget.checkins
          ? await api.checkins(eventId: _groupId, q: q)
          : await api.mobilizations(driveId: _groupId, q: q);
      if (mounted) {
        setState(() {
          _rows = rows;
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
    final color = widget.checkins ? AppColors.teal : AppColors.amber;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(children: [
          Expanded(
            child: DropdownButtonFormField<String?>(
              initialValue: _groupId,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.checkins ? 'Event' : 'Drive', isDense: true),
              items: [
                DropdownMenuItem(value: null, child: Text(widget.checkins ? 'All events' : 'All drives')),
                for (final g in _groups)
                  DropdownMenuItem(value: g.id, child: Text(g.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() => _groupId = v);
                _load();
              },
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: TextField(
          controller: _search,
          decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search), hintText: 'Search name or ID number', isDense: true),
          onChanged: (_) {
            _debounce?.cancel();
            _debounce = Timer(const Duration(milliseconds: 350), _load);
          },
        ),
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
                              title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('ID ${maskId(p.nationalId)} · ${p.ward}\n${p.groupName}', maxLines: 2),
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
