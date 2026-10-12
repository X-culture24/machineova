import 'package:flutter/material.dart';

import '../api/client.dart';
import '../offline/store.dart';
import '../offline/sync.dart';
import '../widgets/offline_banner.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'voter_form.dart';

/// Teal flow: pick event → look up ID → confirm → check in → next voter.
class CheckinFlow extends StatefulWidget {
  const CheckinFlow({super.key});
  @override
  State<CheckinFlow> createState() => _CheckinFlowState();
}

class _CheckinFlowState extends State<CheckinFlow> {
  List<EventItem>? _events;
  EventItem? _event;
  String? _loadError;

  final _id = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _f = PersonFields();
  Lookup? _lookup;
  bool _outside = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      final events = await api.events(activeOnly: true);
      setState(() {
        _events = events;
        _event = events.length == 1 ? events.first : null;
      });
    } catch (e) {
      setState(() => _loadError = errorText(e));
    }
  }

  @override
  void dispose() {
    _id.dispose();
    _f.dispose();
    super.dispose();
  }

  void _reset() {
    _id.clear();
    _f.clear();
    setState(() {
      _lookup = null;
      _outside = false;
      _error = null;
    });
  }

  Future<void> _pickEvent() async {
    final picked = await pickFrom<EventItem>(context, 'Choose your event', _events!, (e) => e.name, (e) => e.area);
    if (picked != null) {
      _reset();
      setState(() => _event = picked);
    }
  }

  Future<void> _doLookup() async {
    if (_event == null || _id.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final l = await api.checkinLookup(_event!.id, _id.text);
      setState(() => _lookup = l);
    } catch (e) {
      if (isNetworkError(e)) {
        // No signal: record now, verify against the register when the phone syncs.
        final seen = await ledger.checkedInToday(_event!.id, _id.text.replaceAll(' ', ''));
        setState(() => _lookup = seen == null
            ? Lookup.offline()
            : Lookup.offline(status: 'already_checked_in', previous: Prior.local(seen)));
        return;
      }
      setState(() {
        _lookup = null;
        _error = "Can't look up: ${errorText(e)}";
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doCheckin() async {
    if (!(_form.currentState?.validate() ?? true)) return;
    final inRegister = _lookup?.voter != null;
    final needsIdentity = !inRegister || _lookup!.voter!.missingIdentity;
    final nid = _id.text.replaceAll(' ', '');
    final name = _lookup?.voter?.name ?? (_f.name.text.trim().isEmpty ? 'ID $nid' : _f.name.text.trim());
    setState(() => _busy = true);
    try {
      final r = await api.checkin(
        _event!.id,
        {'national_id': nid, ..._f.toJson(identity: needsIdentity, location: _outside || !inRegister)},
        label: 'Check-in: $name · ${_event!.name}',
      );
      await ledger.add(kind: 'checkin', group: _event!.id, nationalId: nid, name: name);
      if (!mounted) return;
      final data = r.data;
      final out = data is Map && data['in_region'] == false ? ' (out of region)' : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: r.queued ? AppColors.amber : AppColors.green,
        content: Text(r.queued ? '$name saved on this phone — will sync when online' : '✓ $name checked in$out'),
      ));
      _reset();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Check in', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(child: Column(children: [const OfflineBanner(), Expanded(child: _body())])),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Notice(_loadError!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off));
    }
    if (_events == null) return const Center(child: CircularProgressIndicator());
    if (_events!.isEmpty) {
      return const EmptyNote("You're not assigned to any active event.\nAsk an admin to assign you.");
    }
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Scan or enter an ID to mark a voter present.', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      GroupBanner(
        kicker: _events!.length > 1 ? 'EVENT · TAP TO SWITCH' : 'EVENT',
        title: _event?.name ?? 'Choose your event',
        subtitle: _event?.area ?? '',
        color: AppColors.teal,
        soft: AppColors.tealSoft,
        onTap: _events!.length > 1 ? _pickEvent : null,
      ),
      if (_event != null) ...[
        const SizedBox(height: 12),
        IdEntry(
          controller: _id,
          color: AppColors.teal,
          busy: _busy,
          onLookup: _doLookup,
          onChanged: () {
            if (_lookup != null || _error != null) {
              setState(() {
                _lookup = null;
                _error = null;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        if (_error != null) Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
        if (_lookup != null) _result(_lookup!),
      ],
    ]);
  }

  Widget _result(Lookup l) {
    if (l.isOffline) return _offlineForm();
    switch (l.status) {
      case 'not_on_list':
        return const Notice('Not on the participant list. This event is list-only and this ID isn\'t approved.',
            fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.block);
      case 'already_checked_in':
        final p = l.previous;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Notice('Already checked in today${p == null ? '' : ' at ${fmtTime(p.at)} by ${p.by}'}. Move on.',
              fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.check_circle_outline),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _reset, child: const Text('Next voter')),
        ]);
    }
    final v = l.voter;
    return SectionCard(
      title: 'Confirm & check in',
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (v != null) ...[
            VoterCard(voter: v, color: AppColors.teal, soft: AppColors.tealSoft, inRegion: l.inRegion),
            // Registered, but the register has no name/sex for them: ask the operator.
            if (v.missingIdentity) ...[
              const SizedBox(height: 10),
              const Notice('Registered voter, but their name or sex isn\'t on record. Fill them in.',
                  fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.edit_note),
              const SizedBox(height: 10),
              IdentityInputs(_f),
            ],
          ] else ...[
            const Notice('Not found in the register. Fill in their details.',
                fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.person_search),
            const SizedBox(height: 10),
            IdentityInputs(_f),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _f.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', hintText: '+254…'),
          ),
          if (v != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registered outside this region'),
              value: _outside,
              onChanged: (x) => setState(() => _outside = x),
            ),
          if (_outside || v == null) ...[const SizedBox(height: 8), LocationInputs(_f)],
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _doCheckin, child: Text(_busy ? 'Checking in…' : 'Check in')),
        ]),
      ),
    );
  }

  /// Offline entry: ID (+ whatever details are known); the server completes it from the register on sync.
  Widget _offlineForm() => SectionCard(
        title: 'Save check-in offline',
        child: Form(
          key: _form,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Notice(
              "Offline — can't check the register right now. This check-in is saved on the phone and verified "
              'when you\'re back online. Add the name and sex if the voter might not be on the register.',
              fg: AppColors.amber,
              bg: AppColors.amberSoft,
              icon: Icons.cloud_off,
            ),
            const SizedBox(height: 12),
            IdentityInputs(_f, required: false),
            const SizedBox(height: 10),
            TextFormField(
              controller: _f.phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone', hintText: '+254…'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Registered outside this region'),
              value: _outside,
              onChanged: (x) => setState(() => _outside = x),
            ),
            if (_outside) LocationInputs(_f),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _busy ? null : _doCheckin, child: Text(_busy ? 'Saving…' : 'Check in (save offline)')),
          ]),
        ),
      );
}
