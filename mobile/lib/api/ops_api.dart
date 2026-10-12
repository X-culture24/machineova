// Election Ops models and calls (/api/ops/*).
import 'client.dart';

int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double? _dn(dynamic v) => (v as num?)?.toDouble();

class OpsStation {
  final String code, name, county, constituency, ward, status;
  final int registered, agents, openIncidents, resultsSubmitted;
  final int? cast;
  final double? turnout;
  final String? lastIncident;

  OpsStation.fromJson(Map<String, dynamic> j)
      : code = j['code'],
        name = j['name'],
        county = j['county'],
        constituency = j['constituency'],
        ward = j['ward'],
        status = j['status'],
        registered = _i(j['registered']),
        agents = _i(j['agents']),
        openIncidents = _i(j['open_incidents']),
        resultsSubmitted = _i(j['results_submitted']),
        cast = (j['cast'] as num?)?.toInt(),
        turnout = _dn(j['turnout']),
        lastIncident = j['last_incident'];

  bool get uncovered => agents == 0;
}

class AttentionItem {
  final String code, name, area, reason, kind, action;
  AttentionItem.fromJson(Map<String, dynamic> j)
      : code = j['code'],
        name = j['name'],
        area = j['area'],
        reason = j['reason'],
        kind = j['kind'],
        action = j['action'];
}

class OpsOverview {
  final String electionName, scopeLabel;
  final int stations, reported, open, closed, cast, registered, issues, uncovered, toVerify, agents;
  final double turnout;
  final List<AttentionItem> attention;

  OpsOverview.fromJson(Map<String, dynamic> j)
      : electionName = j['election']['name'],
        scopeLabel = j['scope_label'],
        stations = _i(j['stations']),
        reported = _i(j['reported']),
        open = _i(j['open']),
        closed = _i(j['closed']),
        cast = _i(j['cast']),
        registered = _i(j['registered']),
        issues = _i(j['issues']),
        uncovered = _i(j['uncovered']),
        toVerify = _i(j['to_verify']),
        agents = _i(j['agents']),
        turnout = _dn(j['turnout']) ?? 0,
        attention = [for (final a in j['attention'] as List) AttentionItem.fromJson(a)];
}

class OpsPerson {
  final String id, name, role, area;
  final String? phone, nationalId, stationCode, stationName;
  OpsPerson.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        role = j['role'],
        area = j['area'] ?? '',
        phone = j['phone'],
        nationalId = j['national_id'],
        stationCode = j['station_code'],
        stationName = j['station_name'];
}

class StationEventItem {
  final String kind, message;
  final String? by;
  final DateTime at;
  StationEventItem.fromJson(Map<String, dynamic> j)
      : kind = j['kind'],
        message = j['message'],
        by = j['by'],
        at = DateTime.parse(j['at']).toLocal();
}

class OpenIncident {
  final String id, type, description, reportedBy;
  final DateTime createdAt;
  final bool resolved;
  OpenIncident.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        type = j['type'],
        description = j['description'] ?? '',
        reportedBy = j['reported_by'],
        createdAt = DateTime.parse(j['created_at']).toLocal(),
        resolved = j['resolved_at'] != null;
}

class PositionRef {
  final String id, name, level;
  final bool submitted;

  /// Agents' Form 37A waits for a manager; only verified results count.
  final bool verified;
  PositionRef(this.id, this.name, this.level, this.submitted, {this.verified = false});
}

class StationDetail {
  final OpsStation station;
  final List<OpsPerson> agents;
  final List<StationEventItem> events;
  final List<OpenIncident> incidents;
  final Map<int, int> turnout; // slot hour → cumulative
  final List<PositionRef> positions;
  final List<int> slots;
  final bool canAct, canAssign, canVerify;

  StationDetail.fromJson(Map<String, dynamic> j)
      : station = OpsStation.fromJson(j['station']),
        agents = [
          for (final a in j['agents'] as List)
            OpsPerson.fromJson({...a as Map<String, dynamic>, 'role': 'agent', 'area': ''})
        ],
        events = [for (final e in j['events'] as List) StationEventItem.fromJson(e)],
        incidents = [for (final i in j['incidents'] as List) OpenIncident.fromJson(i)],
        turnout = {for (final t in j['turnout'] as List) _i(t['hour']): _i(t['count'])},
        positions = [
          for (final r in j['results'] as List)
            PositionRef(r['position']['id'], r['position']['name'], r['position']['level'], r['submitted_at'] != null,
                verified: r['verified_at'] != null)
        ],
        slots = [for (final s in j['turnout_slots'] as List) _i(s)],
        canAct = j['can_act'] ?? false,
        canAssign = j['can_assign'] ?? false,
        canVerify = j['can_verify'] ?? false;
}

class RaceCandidate {
  final String id, name;
  final String? party;
  RaceCandidate(this.id, this.name, this.party);
}

class StationResults {
  final String positionName;
  final List<RaceCandidate> candidates;
  final Map<String, int> votes;
  final int? rejected, turnout;
  final bool submitted;

  StationResults.fromJson(Map<String, dynamic> j)
      : positionName = j['position']['name'],
        candidates = [for (final c in j['candidates'] as List) RaceCandidate(c['id'], c['name'], c['party_code'])],
        votes = {for (final e in (j['votes'] as Map).entries) e.key as String: _i(e.value)},
        rejected = (j['rejected'] as num?)?.toInt(),
        turnout = (j['turnout'] as num?)?.toInt(),
        submitted = j['submitted_at'] != null;
}

class PoolAgent {
  final String id, name;
  final String? phone, nationalId, assignedTo;
  PoolAgent.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        phone = j['phone'],
        nationalId = j['national_id'],
        assignedTo = j['assigned_to'];
}

const statusLabels = {
  'not_open': 'Not open',
  'open': 'Open',
  'reporting': 'Reporting',
  'closed': 'Closed',
  'issue': 'Issue'
};
const incidentTypes = [
  'KIEMS kit failure',
  'Ballot paper shortage',
  'Security concern',
  'Agent absent',
  'Voter intimidation',
  'Other'
];

String slotLabel(int h) => '${h % 12 == 0 ? 12 : h % 12} ${h < 12 ? 'AM' : 'PM'}';

class OpsApi {
  final ApiClient c;
  const OpsApi(this.c);

  String _p(String code) => Uri.encodeComponent(code);

  // ---- reads: cached, so they open offline ----

  Future<OpsOverview> overview() async => OpsOverview.fromJson(await c.get('/api/ops/overview'));

  /// All stations in scope (one cached copy); status and search filter on the phone so they work offline.
  Future<(List<OpsStation>, Map<String, int>)> stations({String? status, String? q}) async {
    final r = await c.get('/api/ops/stations', query: {'page_size': '200'});
    final all = [for (final s in r['items'] as List) OpsStation.fromJson(s)];
    final needle = (q ?? '').trim().toLowerCase();
    final shown = all.where((s) {
      if (status == 'uncovered' ? !s.uncovered : (status != null && s.status != status)) return false;
      return needle.isEmpty || '${s.name} ${s.code} ${s.ward}'.toLowerCase().contains(needle);
    }).toList();
    return (shown, {for (final e in (r['counts'] as Map).entries) e.key as String: _i(e.value)});
  }

  Future<StationDetail> station(String code) async =>
      StationDetail.fromJson(await c.get('/api/ops/stations/${_p(code)}'));

  Future<StationResults> stationResults(String code, String positionId) async =>
      StationResults.fromJson(await c.get('/api/ops/stations/${_p(code)}/results', query: {'position_id': positionId}));

  Future<List<PoolAgent>> agentPool(String code) async {
    final r = await c.get('/api/ops/stations/${_p(code)}/agent-pool');
    return [for (final a in r['agents'] as List) PoolAgent.fromJson(a)];
  }

  Future<List<OpsPerson>> people({String? role, String? q}) async {
    final r = await c.get('/api/ops/people', query: {'role': role, 'page_size': '200'});
    final needle = (q ?? '').trim().toLowerCase();
    return [
      for (final p in r['items'] as List)
        if (needle.isEmpty || '${p['name']} ${p['phone']} ${p['national_id']}'.toLowerCase().contains(needle))
          OpsPerson.fromJson(p),
    ];
  }

  // ---- writes: sent now, or queued on the phone and replayed safely later ----

  Future<SendResult> setStatus(String code, String status, String note) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/status', {'status': status, 'note': note},
          label: 'Status → ${statusLabels[status]} · $code', scope: 'station:$code');

  Future<SendResult> recordTurnout(String code, int slot, int cumulative) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/turnout', {'slot_hour': slot, 'cumulative': cumulative},
          label: 'Turnout ${slotLabel(slot)} — $cumulative · $code', scope: 'station:$code');

  Future<SendResult> reportIncident(String code, String type, String description) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/incidents', {'type': type, 'description': description},
          label: 'Incident: $type · $code', scope: 'station:$code');

  Future<SendResult> resolveIncident(String code, String id, String resolution) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/incidents/$id/resolve', {'resolution': resolution},
          label: 'Incident resolved · $code', scope: 'station:$code');

  Future<SendResult> submitResults(
          String code, String positionId, String positionName, Map<String, int> votes, int rejected) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/results',
          {'position_id': positionId, 'votes': votes, 'rejected': rejected, 'confirm': true},
          label: 'Form 37A: $positionName · $code', scope: 'station:$code');

  Future<SendResult> verifyResults(String code, String positionId, String positionName) =>
      c.send('POST', '/api/ops/stations/${_p(code)}/results/verify', {'position_id': positionId},
          label: 'Verify Form 37A: $positionName · $code', scope: 'station:$code');

  Future<SendResult> assignAgent(String code, String userId, String name) =>
      c.send('PUT', '/api/ops/stations/${_p(code)}/agents/$userId', null,
          label: 'Assign $name · $code', scope: 'station:$code');

  Future<SendResult> unassignAgent(String code, String userId, String name) =>
      c.send('DELETE', '/api/ops/stations/${_p(code)}/agents/$userId', null,
          label: 'Remove $name · $code', scope: 'station:$code');
}

final opsApi = OpsApi(api);
