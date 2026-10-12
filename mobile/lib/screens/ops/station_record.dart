import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/client.dart';
import '../../api/ops_api.dart';
import '../../offline/sync.dart';
import '../../widgets/offline_banner.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'ops_widgets.dart';

enum QuickAction { status, assign, turnout, incident, results }

/// Full-screen station record (the dashboard's drawer); quick edits open as bottom sheets.
class StationRecordScreen extends StatefulWidget {
  final String code;
  final QuickAction? initialAction;
  const StationRecordScreen({super.key, required this.code, this.initialAction});
  @override
  State<StationRecordScreen> createState() => _StationRecordScreenState();
}

class _StationRecordScreenState extends State<StationRecordScreen> {
  StationDetail? _d;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.initialAction != null && _d != null && _d!.canAct && mounted) _run(widget.initialAction!);
    });
  }

  Future<void> _load() async {
    try {
      final d = await opsApi.station(widget.code);
      if (mounted) {
        setState(() {
          _d = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _run(QuickAction a) async {
    final d = _d!;
    final sheet = switch (a) {
      QuickAction.status => _StatusSheet(d),
      QuickAction.assign => _AssignSheet(d),
      QuickAction.turnout => _TurnoutSheet(d),
      QuickAction.incident => _IncidentSheet(d),
      QuickAction.results => _ResultsSheet(d),
    };
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom), child: sheet),
    );
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: AppColors.green, content: Text(saved)));
    }
    _load();
  }

  Future<void> _resolve(OpenIncident i) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Resolve: ${i.type}'),
        content: TextField(
            controller: ctrl, decoration: const InputDecoration(labelText: 'How was it resolved?'), autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Resolve')),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        final r = await opsApi.resolveIncident(widget.code, i.id, ctrl.text.trim());
        if (r.queued && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Saved on this phone — will sync when online')));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorText(e))));
      }
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      appBar: AppBar(title: const Text('Station')),
      body: _error != null && d == null
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Notice(errorText(_error!), fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline))
          : d == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  const OfflineBanner(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      // Rebuild when queued edits for this station sync.
                      child: ListenableBuilder(listenable: outbox, builder: (_, __) => _body(d)),
                    ),
                  ),
                ]),
    );
  }

  Widget _body(StationDetail d) {
    final s = d.station;
    final open = d.incidents.where((i) => !i.resolved).toList();
    Widget label(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
          child: Text(t,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w700, letterSpacing: .8)),
        );
    Widget action(QuickAction a, String title, String sub, {IconData? icon}) => Card(
          child: ListTile(
            minTileHeight: 56,
            leading: Icon(icon, color: AppColors.teal),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.teal)),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _run(a),
          ),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
      Text(s.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text('${s.code} · ${s.ward} Ward · ${s.constituency}', style: const TextStyle(color: AppColors.muted)),
      const SizedBox(height: 8),
      Wrap(spacing: 6, children: [StatusPill(s.status), CoveragePill(s.agents)]),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(child: StatTile('REGISTERED', fmtNum(s.registered))),
        const SizedBox(width: 10),
        Expanded(
            child: StatTile('TURNOUT', s.turnout == null ? '—' : fmtPct(s.turnout!),
                valueColor: AppColors.teal, caption: s.cast == null ? null : '${fmtNum(s.cast!)} cast')),
      ]),
      if (d.canAct) ...[
        label('QUICK ACTIONS'),
        action(QuickAction.status, 'Update status', 'Open · Reporting · Closed · Issue', icon: Icons.flag_outlined),
        const SizedBox(height: 8),
        action(QuickAction.turnout, 'Record turnout', 'Cumulative, by time slot', icon: Icons.how_to_vote_outlined),
        const SizedBox(height: 8),
        action(QuickAction.incident, 'Report incident', 'Flags as Issue instantly', icon: Icons.report_outlined),
        const SizedBox(height: 8),
        action(QuickAction.results, 'Submit & verify results', 'Form 37A figures per candidate',
            icon: Icons.fact_check_outlined),
        if (d.canAssign) ...[
          const SizedBox(height: 8),
          action(QuickAction.assign, 'Assign agent', 'Two taps from the ward pool', icon: Icons.person_add_alt),
        ],
      ],
      if (open.isNotEmpty) ...[
        label('OPEN INCIDENTS'),
        for (final i in open)
          Card(
            color: AppColors.redSoft,
            child: ListTile(
              title: Text(i.type, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text([if (i.description.isNotEmpty) i.description, '${i.reportedBy} · ${fmtTime(i.createdAt)}']
                  .join('\n')),
              trailing: d.canAssign ? TextButton(onPressed: () => _resolve(i), child: const Text('Resolve')) : null,
            ),
          ),
      ],
      if (outbox.forScope('station:${s.code}').isNotEmpty) ...[
        label('SAVED ON THIS PHONE — WAITING TO SYNC'),
        for (final q in outbox.forScope('station:${s.code}'))
          Card(
            color: q.state == OutboxState.failed ? AppColors.redSoft : AppColors.amberSoft,
            child: ListTile(
              leading: Icon(q.state == OutboxState.failed ? Icons.error_outline : Icons.schedule,
                  color: q.state == OutboxState.failed ? AppColors.red : AppColors.amber),
              title: Text(q.label.replaceAll(' · ${s.code}', '')),
              subtitle:
                  Text(q.state == OutboxState.failed ? (q.error ?? 'Rejected') : 'Recorded ${fmtTime(q.recordedAt)}'),
            ),
          ),
      ],
      label(d.agents.length == 1 ? 'ASSIGNED AGENT' : 'ASSIGNED AGENTS'),
      if (d.agents.isEmpty) const Text('No agent assigned yet.', style: TextStyle(color: AppColors.muted)),
      for (final a in d.agents)
        Card(
          child: ListTile(
            leading: Avatar(a.name),
            title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('${a.phone ?? '—'} · ID ${a.nationalId ?? '—'}'),
            trailing: ContactButtons(a.phone),
          ),
        ),
      label('FORM 37A'),
      for (final p in d.positions)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text(p.name)),
            p.submitted
                ? const Pill('VERIFIED', fg: AppColors.green, bg: AppColors.greenSoft)
                : const Pill('PENDING', fg: AppColors.muted, bg: Color(0xFFEFF2F1)),
          ]),
        ),
      label('ACTIVITY'),
      if (d.events.isEmpty) const Text('Nothing yet.', style: TextStyle(color: AppColors.muted)),
      for (final e in d.events)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: Icon(Icons.circle,
              size: 10,
              color: switch (e.kind) {
                'incident' => AppColors.red,
                'resolved' || 'results' => AppColors.green,
                _ => AppColors.teal,
              }),
          title: Text(e.message),
          subtitle: Text('${fmtDateTime(e.at)}${e.by == null ? '' : ' · ${e.by}'}'),
        ),
    ]);
  }
}

// ---------------- quick-edit sheets ----------------

/// Shared sheet scaffold: title, subtitle, body, error and a 44px+ save button.
class _Sheet extends StatelessWidget {
  final String title, subtitle;
  final List<Widget> children;
  final String? error;
  final String saveLabel;
  final bool busy;
  final VoidCallback? onSave;
  final Color color;
  const _Sheet({
    required this.title,
    required this.subtitle,
    required this.children,
    required this.saveLabel,
    required this.onSave,
    this.error,
    this.busy = false,
    this.color = AppColors.teal,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          Text(subtitle, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 14),
          if (error != null) ...[
            Notice(error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
            const SizedBox(height: 10),
          ],
          ...children,
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: color),
            onPressed: busy ? null : onSave,
            child: Text(busy ? 'Saving…' : saveLabel),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ]),
      );
}

String _sub(StationDetail d) => '${d.station.name} · ${d.station.code}';

/// Runs a save, pops with a success message, or shows the error.
mixin _Saving<T extends StatefulWidget> on State<T> {
  bool busy = false;
  String? error;
  Future<void> save(Future<SendResult> Function() fn, String done) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await fn();
      if (mounted) Navigator.pop(context, r.queued ? '$done — saved on this phone, will sync' : done);
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = errorText(e);
        });
      }
    }
  }
}

class _StatusSheet extends StatefulWidget {
  final StationDetail d;
  const _StatusSheet(this.d);
  @override
  State<_StatusSheet> createState() => _StatusSheetState();
}

class _StatusSheetState extends State<_StatusSheet> with _Saving {
  late String _status = widget.d.station.status == 'not_open' ? 'open' : widget.d.station.status;
  final _note = TextEditingController();
  static const _help = {
    'open': 'Voting in progress',
    'reporting': 'Figures coming in from the agent',
    'closed': 'Polls closed — awaiting verification',
    'issue': 'Needs attention now',
  };

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Update station status',
        subtitle: _sub(widget.d),
        error: error,
        busy: busy,
        saveLabel: 'Update status',
        onSave: () => save(() => opsApi.setStatus(widget.d.station.code, _status, _note.text), 'Status updated'),
        children: [
          RadioGroup<String>(
            groupValue: _status,
            onChanged: (v) => setState(() => _status = v ?? _status),
            child: Column(children: [
              for (final e in _help.entries)
                RadioListTile<String>(
                  value: e.key,
                  title: Text(statusLabels[e.key]!, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(e.value),
                ),
            ]),
          ),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
        ],
      );
}

class _TurnoutSheet extends StatefulWidget {
  final StationDetail d;
  const _TurnoutSheet(this.d);
  @override
  State<_TurnoutSheet> createState() => _TurnoutSheetState();
}

class _TurnoutSheetState extends State<_TurnoutSheet> with _Saving {
  late int _slot;
  final _value = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().hour;
    _slot = widget.d.slots.lastWhere((h) => h <= now, orElse: () => widget.d.slots.first);
    _value.text = widget.d.turnout[_slot]?.toString() ?? '';
  }

  /// Same rules as the server: cumulative, never above registered — including figures still queued.
  String? _cumulativeProblem(int v) {
    final s = widget.d.station;
    if (s.registered > 0 && v > s.registered) return 'Turnout can\'t exceed ${fmtNum(s.registered)} registered voters';
    final known = {...widget.d.turnout};
    for (final q in outbox.forScope('station:${s.code}')) {
      final b = q.body;
      if (q.path.endsWith('/turnout') && b != null) {
        known[(b['slot_hour'] as num).toInt()] = (b['cumulative'] as num).toInt();
      }
    }
    for (final e in known.entries) {
      if (e.key < _slot && e.value > v) {
        return 'Turnout is cumulative — ${slotLabel(e.key)} already has ${fmtNum(e.value)}';
      }
      if (e.key > _slot && e.value < v) return '${slotLabel(e.key)} already has ${fmtNum(e.value)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.d.station;
    return _Sheet(
      title: 'Record voter turnout',
      subtitle: _sub(widget.d),
      error: error,
      busy: busy,
      saveLabel: 'Save turnout',
      onSave: () {
        final v = int.tryParse(_value.text.trim());
        if (v == null) {
          setState(() => error = 'Enter the number of voters who have voted');
          return;
        }
        final problem = _cumulativeProblem(v);
        if (problem != null) {
          setState(() => error = problem);
          return;
        }
        save(() => opsApi.recordTurnout(s.code, _slot, v), 'Turnout saved for ${slotLabel(_slot)}');
      },
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final h in widget.d.slots)
            ChoiceChip(
              label: Text('${slotLabel(h)}${widget.d.turnout.containsKey(h) ? ' ✓' : ''}'),
              selected: _slot == h,
              onSelected: (_) => setState(() {
                _slot = h;
                _value.text = widget.d.turnout[h]?.toString() ?? '';
              }),
            ),
        ]),
        const SizedBox(height: 14),
        TextField(
          controller: _value,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          decoration: const InputDecoration(labelText: 'Cumulative voters who have voted', hintText: 'e.g. 412'),
        ),
        const SizedBox(height: 6),
        Text(
          'Registered ${fmtNum(s.registered)} · recorded so far '
          '${s.cast == null ? '—' : '${fmtNum(s.cast!)} (${fmtPct(s.cast! / (s.registered == 0 ? 1 : s.registered))})'}',
          style: const TextStyle(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _IncidentSheet extends StatefulWidget {
  final StationDetail d;
  const _IncidentSheet(this.d);
  @override
  State<_IncidentSheet> createState() => _IncidentSheetState();
}

class _IncidentSheetState extends State<_IncidentSheet> with _Saving {
  String _type = incidentTypes.first;
  final _desc = TextEditingController();

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Report an incident',
        subtitle: _sub(widget.d),
        error: error,
        busy: busy,
        color: AppColors.red,
        saveLabel: 'Report incident',
        onSave: () =>
            save(() => opsApi.reportIncident(widget.d.station.code, _type, _desc.text.trim()), 'Incident reported'),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in incidentTypes)
              ChoiceChip(
                label: Text(t),
                selected: _type == t,
                selectedColor: AppColors.redSoft,
                onSelected: (_) => setState(() => _type = t),
              ),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration:
                const InputDecoration(labelText: 'What happened?', hintText: 'Who is affected, what\'s needed…'),
          ),
          const SizedBox(height: 6),
          const Text('Reporting flags this station as Issue and puts it at the top of the action list.',
              style: TextStyle(color: AppColors.muted, fontSize: 12)),
        ],
      );
}

class _ResultsSheet extends StatefulWidget {
  final StationDetail d;
  const _ResultsSheet(this.d);
  @override
  State<_ResultsSheet> createState() => _ResultsSheetState();
}

class _ResultsSheetState extends State<_ResultsSheet> with _Saving {
  late String? _positionId =
      (widget.d.positions.where((p) => !p.submitted).firstOrNull ?? widget.d.positions.firstOrNull)?.id;
  StationResults? _form;
  final Map<String, TextEditingController> _votes = {};
  final _rejected = TextEditingController(text: '0');
  bool _confirm = false;

  @override
  void initState() {
    super.initState();
    _loadForm();
  }

  @override
  void dispose() {
    for (final c in _votes.values) {
      c.dispose();
    }
    _rejected.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    final id = _positionId;
    if (id == null) return;
    setState(() => _form = null);
    try {
      final f = await opsApi.stationResults(widget.d.station.code, id);
      if (!mounted) return;
      for (final c in _votes.values) {
        c.dispose();
      }
      _votes
        ..clear()
        ..addAll({for (final c in f.candidates) c.id: TextEditingController(text: '${f.votes[c.id] ?? 0}')});
      _rejected.text = '${f.rejected ?? 0}';
      setState(() {
        _form = f;
        _confirm = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    }
  }

  int get _total =>
      _votes.values.fold(0, (s, c) => s + (int.tryParse(c.text) ?? 0)) + (int.tryParse(_rejected.text) ?? 0);

  @override
  Widget build(BuildContext context) {
    final f = _form;
    final mismatch = f?.turnout != null && _total != f!.turnout;
    return _Sheet(
      title: 'Submit & verify results',
      subtitle: '${_sub(widget.d)} · Form 37A',
      error: error,
      busy: busy,
      saveLabel: 'Submit & verify',
      onSave: (f == null || f.candidates.isEmpty || !_confirm)
          ? null
          : () => save(
              () => opsApi.submitResults(
                  widget.d.station.code,
                  _positionId!,
                  f.positionName,
                  {for (final e in _votes.entries) e.key: int.tryParse(e.value.text) ?? 0},
                  int.tryParse(_rejected.text) ?? 0),
              '${f.positionName} results verified'),
      children: [
        if (widget.d.positions.isEmpty) const Text('This election has no positions yet.'),
        if (widget.d.positions.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: _positionId,
            decoration: const InputDecoration(labelText: 'Position'),
            items: [
              for (final p in widget.d.positions)
                DropdownMenuItem(value: p.id, child: Text('${p.name}${p.submitted ? ' ✓' : ''}')),
            ],
            onChanged: (v) {
              _positionId = v;
              _loadForm();
            },
          ),
        const SizedBox(height: 12),
        if (f == null && widget.d.positions.isNotEmpty) const Center(child: CircularProgressIndicator()),
        if (f != null && f.candidates.isEmpty)
          const Notice('No candidates are set up for this race yet.',
              fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.info_outline),
        if (f != null && f.candidates.isNotEmpty) ...[
          for (final c in f.candidates)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(child: Text('${c.name} · ${c.party ?? 'IND'}')),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _votes[c.id],
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.end,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ]),
            ),
          Row(children: [
            const Expanded(child: Text('Rejected / spoilt ballots')),
            SizedBox(
              width: 110,
              child: TextField(
                controller: _rejected,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.end,
                onChanged: (_) => setState(() {}),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            'Total ${fmtNum(_total)} · recorded turnout ${f.turnout == null ? '—' : fmtNum(f.turnout!)}'
            '${mismatch ? ' — check against the form' : ''}',
            style: TextStyle(
                color: mismatch ? AppColors.amber : AppColors.muted, fontWeight: mismatch ? FontWeight.w600 : null),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirm,
            onChanged: (v) => setState(() => _confirm = v ?? false),
            title: const Text('I confirm these figures match the signed Form 37A from this station.'),
          ),
        ],
      ],
    );
  }
}

class _AssignSheet extends StatefulWidget {
  final StationDetail d;
  const _AssignSheet(this.d);
  @override
  State<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends State<_AssignSheet> {
  List<PoolAgent>? _pool;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await opsApi.agentPool(widget.d.station.code);
      if (mounted) setState(() => _pool = p);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _toggle(PoolAgent a, bool here) async {
    try {
      final r = here
          ? await opsApi.unassignAgent(widget.d.station.code, a.id, a.name)
          : await opsApi.assignAgent(widget.d.station.code, a.id, a.name);
      _changed = true;
      if (r.queued) {
        setState(
            () => _error = 'Offline — ${here ? 'removal' : 'assignment'} of ${a.name} saved on this phone, will sync.');
      } else {
        _load();
      }
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => _Sheet(
        title: 'Assign agents',
        subtitle: '${_sub(widget.d)} · ${widget.d.station.ward} Ward pool',
        error: _error,
        saveLabel: 'Done',
        onSave: () => Navigator.pop(context, _changed ? 'Assignments updated' : null),
        children: [
          if (_pool == null) const Center(child: CircularProgressIndicator()),
          if (_pool != null && _pool!.isEmpty) const EmptyNote('No agents registered in this ward yet.'),
          for (final a in _pool ?? <PoolAgent>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(a.name),
              title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(a.assignedTo == null
                  ? 'Available'
                  : a.assignedTo == widget.d.station.code
                      ? 'At this station'
                      : 'At ${a.assignedTo}'),
              trailing: a.assignedTo == widget.d.station.code
                  ? OutlinedButton(onPressed: () => _toggle(a, true), child: const Text('Remove'))
                  : FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(88, 44)),
                      onPressed: () => _toggle(a, false),
                      child: const Text('Assign')),
            ),
        ],
      );
}
