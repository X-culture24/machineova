import 'package:flutter/material.dart';

import '../api/client.dart';
import '../offline/store.dart';
import '../offline/sync.dart';
import '../widgets/offline_banner.dart';
import '../api/models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'voter_form.dart';

/// Amber flow: pick drive → look up ID → fill details → register; shows progress to target.
class MobilizeFlow extends StatefulWidget {
  const MobilizeFlow({super.key});
  @override
  State<MobilizeFlow> createState() => _MobilizeFlowState();
}

class _MobilizeFlowState extends State<MobilizeFlow> {
  List<Drive>? _drives;
  Drive? _drive;
  String? _loadError;

  final _id = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _f = PersonFields();
  Lookup? _lookup;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDrives();
  }

  Future<void> _loadDrives() async {
    try {
      final drives = await api.drives(activeOnly: true);
      setState(() {
        _drives = drives;
        _drive = drives.length == 1 ? drives.first : null;
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
      _error = null;
    });
  }

  Future<void> _pickDrive() async {
    final picked = await pickFrom<Drive>(context, 'Choose your drive', _drives!, (d) => d.name, (d) => d.area);
    if (picked != null) {
      _reset();
      setState(() => _drive = picked);
    }
  }

  Future<void> _doLookup() async {
    if (_drive == null || _id.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final l = await api.mobilizeLookup(_id.text);
      final v = l.voter;
      if (v != null) {
        // Pre-fill editable details from the register.
        _f.name.text = v.name;
        _f.sex = v.sex;
        _f.dob.text = v.dob;
        _f.county.text = v.county;
        _f.constituency.text = v.constituency;
        _f.ward.text = v.ward;
      }
      setState(() => _lookup = l);
    } catch (e) {
      if (isNetworkError(e)) {
        // No signal: register now; the server dedups and fills blanks from the register on sync.
        final seen = await ledger.mobilized(_id.text.replaceAll(' ', ''));
        setState(() => _lookup = seen == null
            ? Lookup.offline()
            : Lookup.offline(status: 'already_mobilized', previous: Prior.local(seen, where: 'a drive')));
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

  Future<void> _doRegister() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final nid = _id.text.replaceAll(' ', '');
    final name = _f.name.text.trim().isEmpty ? 'ID $nid' : _f.name.text.trim();
    setState(() => _busy = true);
    try {
      final r = await api.mobilize(_drive!.id, {'national_id': nid, ..._f.toJson(identity: true, location: true)},
          label: 'Mobilized: $name · ${_drive!.name}');
      await ledger.add(kind: 'mobilization', group: _drive!.id, nationalId: nid, name: name);
      // Offline (or cached), show progress optimistically until the next refresh.
      final fresh = r.queued ? null : await api.drive(_drive!.id).catchError((_) => _drive!.bumped());
      final updated = fresh ?? _drive!.bumped();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: AppColors.amber,
        content: Text(r.queued ? '$name saved on this phone — will sync when online' : '✓ $name registered'),
      ));
      _reset();
      setState(() => _drive = updated);
    } on ApiException catch (e) {
      final prev = e.body['previous'];
      setState(() => _error =
          prev is Map<String, dynamic> ? 'Already mobilized by ${prev['by']} in ${prev['where']}.' : e.message);
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mobilize', style: TextStyle(fontWeight: FontWeight.w800))),
      body: SafeArea(child: Column(children: [const OfflineBanner(), Expanded(child: _body())])),
    );
  }

  Widget _body() {
    if (_loadError != null) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Notice(_loadError!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off));
    }
    if (_drives == null) return const Center(child: CircularProgressIndicator());
    if (_drives!.isEmpty) {
      return const EmptyNote("You're not assigned to any active drive.\nAsk an admin to assign you.");
    }
    final d = _drive;
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Register voters your team reaches in the field.', style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 12),
      GroupBanner(
        kicker: _drives!.length > 1 ? 'DRIVE · TAP TO SWITCH' : 'DRIVE',
        title: d?.name ?? 'Choose your drive',
        subtitle: d?.area ?? '',
        color: AppColors.amber,
        soft: AppColors.amberSoft,
        onTap: _drives!.length > 1 ? _pickDrive : null,
      ),
      if (d != null) ...[
        const SizedBox(height: 12),
        _ProgressCard(d),
        const SizedBox(height: 12),
        IdEntry(
          controller: _id,
          color: AppColors.amber,
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
    final offline = l.isOffline;
    if (l.status == 'already_mobilized') {
      final p = l.previous;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Notice(
          'Already mobilized${p == null ? '' : ' by ${p.by} in ${p.where} on ${fmtDateTime(p.at)}'}. No double counting needed.',
          fg: AppColors.amber,
          bg: AppColors.amberSoft,
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 10),
        OutlinedButton(onPressed: _reset, child: const Text('Next voter')),
      ]);
    }
    return SectionCard(
      title: 'Voter details',
      child: Form(
        key: _form,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (offline) ...[
            const Notice(
              "Offline — can't check the register or duplicates right now. This registration is saved on the phone "
              'and checked when you\'re back online. Fill in what you can.',
              fg: AppColors.amber,
              bg: AppColors.amberSoft,
              icon: Icons.cloud_off,
            ),
            const SizedBox(height: 10),
          ] else if (l.voter == null) ...[
            const Notice('Not found in the register. Fill in their details.',
                fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.person_search),
            const SizedBox(height: 10),
          ],
          IdentityInputs(_f, required: !offline),
          const SizedBox(height: 10),
          TextFormField(
            controller: _f.phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', hintText: '+254…'),
          ),
          const SizedBox(height: 10),
          LocationInputs(_f, required: !offline),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.amber),
            onPressed: _busy ? null : _doRegister,
            child: Text(_busy ? 'Registering…' : 'Register'),
          ),
        ]),
      ),
    );
  }
}

class _ProgressCard extends StatelessWidget {
  final Drive d;
  const _ProgressCard(this.d);

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, int v) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 10, color: AppColors.muted, fontWeight: FontWeight.w600)),
            Text(fmtNum(v), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [stat('Mobilized', d.mobilized), stat('Target', d.target), stat('Remaining', d.remaining)]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ProgressLine(d.progress)),
            const SizedBox(width: 10),
            Text(fmtPct(d.progress), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.amber)),
          ]),
        ]),
      ),
    );
  }
}
