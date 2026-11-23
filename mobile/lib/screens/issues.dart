import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../offline/sync.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

// Field issues: the team records each problem met at a training as it happens (no internet on
// the device, a device that fails, a chief's location, sign-in, the app, …) with the chief
// concerned. Recorded with no signal too: the outbox sends it later. The dashboard compiles them
// into the training report (PDF).

class IssuesScreen extends StatefulWidget {
  const IssuesScreen({super.key});
  @override
  State<IssuesScreen> createState() => _IssuesScreenState();
}

class _IssuesScreenState extends State<IssuesScreen> {
  late Future<List<Issue>> _list = api.issues();

  Future<void> _record() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const IssueForm()));
    if (saved == true && mounted) {
      setState(() {
        _list = api.issues();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canWrite = session.me?.canOperate ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Field issues')),
      floatingActionButton: canWrite
          ? FloatingActionButton.extended(
              key: const Key('record-issue'),
              onPressed: _record,
              backgroundColor: AppColors.purple,
              foregroundColor: Colors.white,
              shape: const StadiumBorder(),
              icon: const Icon(Icons.report_problem_outlined),
              label: const Text('Record a problem'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {
      _list = api.issues();
    });
          await _list.catchError((_) => <Issue>[]);
        },
        child: FutureBuilder<List<Issue>>(
          future: _list,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (snap.hasError) {
              return ListView(padding: const EdgeInsets.all(16), children: [
                Notice(errorText(snap.error!), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.wifi_off),
              ]);
            }
            final items = snap.data!;
            final waiting = outbox.forScope('issues').length;
            return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
              const Text('Problems met during the trainings, with the chief concerned. They go into the training report.',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 12),
              if (waiting > 0) ...[
                Notice('$waiting problem${waiting == 1 ? '' : 's'} saved on this phone, sent when there is signal.',
                    fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.cloud_upload_outlined),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty) const EmptyNote('No problems recorded yet.'),
              for (final i in items) _IssueCard(i),
            ]);
          },
        ),
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final Issue i;
  const _IssueCard(this.i);

  @override
  Widget build(BuildContext context) {
    final chief = [i.chiefName, if (i.nationalId.isNotEmpty) 'ID ${i.nationalId}', i.phone, i.location]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(i.categoryLabel, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Pill(i.open ? 'OPEN' : 'RESOLVED',
                fg: i.open ? AppColors.amber : AppColors.green, bg: i.open ? AppColors.amberSoft : AppColors.greenSoft),
          ]),
          const SizedBox(height: 2),
          Text('${i.eventName ?? 'Not at a training'} · ${fmtDateTime(i.reportedAt)} · ${i.reportedBy}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (chief.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(chief, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
          const SizedBox(height: 6),
          Text(i.description),
          if (i.actionTaken.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Action: ${i.actionTaken}', style: const TextStyle(color: AppColors.muted)),
          ],
        ]),
      ),
    );
  }
}

class IssueForm extends StatefulWidget {
  const IssueForm({super.key});
  @override
  State<IssueForm> createState() => _IssueFormState();
}

class _IssueFormState extends State<IssueForm> {
  List<EventItem> _events = [];
  String? _eventId;
  String? _category;
  bool _resolved = false;
  bool _busy = false;
  String? _error, _lookup;
  final _id = TextEditingController(), _name = TextEditingController(), _phone = TextEditingController();
  final _location = TextEditingController(), _what = TextEditingController(), _action = TextEditingController();

  @override
  void initState() {
    super.initState();
    api.events().then((e) {
      if (!mounted) return;
      setState(() {
        _events = e;
        _eventId ??= e.where((x) => x.active).firstOrNull?.id;
      });
    }).catchError((_) {});
  }

  @override
  void dispose() {
    for (final c in [_id, _name, _phone, _location, _what, _action]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _findChief() async {
    final id = _id.text.trim();
    if (_eventId == null || id.isEmpty) return;
    try {
      final c = await api.issueChief(_eventId!, id);
      if (!mounted) return;
      setState(() {
        if (c == null) {
          _lookup = 'Not checked in at this training: type their details.';
          return;
        }
        if (_name.text.isEmpty) _name.text = '${c['name'] ?? ''}';
        if (_phone.text.isEmpty) _phone.text = '${c['phone'] ?? ''}';
        if (_location.text.isEmpty) _location.text = '${c['location'] ?? ''}';
        _lookup = 'Filled from their check-in.';
      });
    } catch (_) {
      if (mounted) setState(() => _lookup = 'No signal: type their details.');
    }
  }

  Future<void> _save() async {
    if (_category == null || _what.text.trim().isEmpty) {
      setState(() => _error = _category == null ? 'Pick the kind of problem.' : 'Describe what happened.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final label = issueCategories[_category] ?? 'Problem';
    try {
      final r = await api.reportIssue({
        'event_id': _eventId,
        'category': _category,
        'chief_name': _name.text,
        'national_id': _id.text,
        'phone': _phone.text,
        'location': _location.text,
        'description': _what.text,
        'action_taken': _action.text,
        'status': _resolved ? 'resolved' : 'open',
      }, label: 'Problem: $label${_name.text.trim().isEmpty ? '' : ' (${_name.text.trim()})'}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.queued ? 'No signal: the problem is saved and will be sent.' : 'Problem recorded.')));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _dec(String label, {String? hint, String? helper}) =>
      InputDecoration(labelText: label, hintText: hint, helperText: helper, helperMaxLines: 2);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Record a problem')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          DropdownButtonFormField<String?>(
            // Rebuilt when the trainings arrive, so the open one shows as chosen.
            key: ValueKey('issue-training-${_events.length}'),
            initialValue: _eventId,
            isExpanded: true,
            decoration: _dec('Training'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Not at a training')),
              for (final e in _events)
                DropdownMenuItem<String?>(value: e.id, child: Text('${e.name}${e.active ? ' (open)' : ''}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _eventId = v),
          ),
          const SizedBox(height: 16),
          const Text('Problem', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in issueCategories.entries)
              ChoiceChip(
                key: Key('issue-cat-${c.key}'),
                label: Text(c.value),
                selected: _category == c.key,
                selectedColor: AppColors.purpleSoft,
                onSelected: (_) => setState(() {
                  _category = c.key;
                  _error = null;
                }),
              ),
          ]),
          const SizedBox(height: 16),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: TextField(
                key: const Key('issue-id'),
                controller: _id,
                keyboardType: TextInputType.number,
                decoration: _dec("Chief's ID number",
                    helper: _lookup ?? (_eventId != null ? 'Find fills the rest if they checked in here.' : null)),
                onSubmitted: (_) => _findChief(),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              // The theme's buttons are full width; this one sits beside the ID field.
              child: SizedBox(
                width: 84,
                child: OutlinedButton(onPressed: _eventId == null ? null : _findChief, child: const Text('Find')),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          TextField(key: const Key('issue-name'), controller: _name, decoration: _dec("Chief's name"), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          TextField(key: const Key('issue-phone'), controller: _phone, keyboardType: TextInputType.phone, decoration: _dec('Phone number')),
          const SizedBox(height: 12),
          TextField(key: const Key('issue-location'), controller: _location, decoration: _dec('Location', hint: 'e.g. Kapropita, Kabarnet')),
          const SizedBox(height: 12),
          TextField(
            key: const Key('issue-what'),
            controller: _what,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            minLines: 3,
            maxLines: 8,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec('What happened', hint: 'Describe the problem as it is: what the chief saw, what was tried…'),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('issue-action'),
            controller: _action,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: _dec('Action taken (optional)', hint: 'e.g. Shared a hotspot'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Resolved'),
            subtitle: const Text('Leave off if it still needs sorting out.'),
            value: _resolved,
            onChanged: (v) => setState(() => _resolved = v),
          ),
          const SizedBox(height: 12),
          // Next to the button, where the eye is when saving.
          if (_error != null) ...[
            Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          FilledButton(
            key: const Key('issue-save'),
            onPressed: _busy ? null : _save,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(_busy ? 'Saving…' : 'Record problem'),
            ),
          ),
        ]),
      );
}
