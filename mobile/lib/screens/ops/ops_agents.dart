import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/ops_api.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'ops_home.dart';
import 'ops_widgets.dart';

/// Agents (and other people) in my area — one tap to call or WhatsApp.
class OpsAgentsScreen extends StatefulWidget {
  const OpsAgentsScreen({super.key});
  @override
  State<OpsAgentsScreen> createState() => _OpsAgentsScreenState();
}

class _OpsAgentsScreenState extends State<OpsAgentsScreen> {
  List<OpsPerson>? _people;
  String? _error;
  String _role = 'agent';
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
      final p = await opsApi.people(role: _role.isEmpty ? null : _role, q: _search.text.trim());
      if (mounted) {
        setState(() {
          _people = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Agents', style: TextStyle(fontWeight: FontWeight.w800))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search), hintText: 'Search name, phone or ID…', isDense: true),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 300), _load);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'agent', label: Text('Agents')),
              ButtonSegment(value: 'manager', label: Text('Managers')),
              ButtonSegment(value: '', label: Text('Everyone')),
            ],
            selected: {_role},
            onSelectionChanged: (s) {
              setState(() => _role = s.first);
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _error != null
                ? ListView(padding: const EdgeInsets.all(16), children: [
                    Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
                  ])
                : _people == null
                    ? const Center(child: CircularProgressIndicator())
                    : _people!.isEmpty
                        ? ListView(children: const [
                            EmptyNote('No one here yet. People are added from the dashboard directory.')
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                            itemCount: _people!.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = _people![i];
                              return ListTile(
                                minTileHeight: 64,
                                leading: Avatar(p.name),
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text([
                                  '${roleTitle(p.role)} · ${p.area}',
                                  if (p.stationName != null)
                                    'At ${p.stationName}'
                                  else if (p.role == 'agent')
                                    'Not assigned',
                                ].join('\n')),
                                isThreeLine: true,
                                trailing: ContactButtons(p.phone),
                              );
                            },
                          ),
          ),
        ),
      ]),
    );
  }
}
