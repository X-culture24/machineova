// Models mirroring the Checkin Go API JSON.

String? _s(dynamic v) => v as String?;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

class Me {
  final String id, name, email, role;
  final bool moduleEvents, moduleMobilization;
  final String? orgName;
  final bool orgActive;
  final String scopeLabel;

  Me.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        email = j['email'],
        role = j['role'],
        moduleEvents = j['module_events'] ?? false,
        moduleMobilization = j['module_mobilization'] ?? false,
        orgName = (j['organization'] as Map?)?['name'],
        orgActive = (j['organization'] as Map?)?['active'] ?? false,
        scopeLabel = j['scope_label'] ?? '';

  bool get canOperate => role != 'viewer';

  static const _opsRoles = {'owner', 'executive', 'admin', 'chief_agent', 'manager', 'agent'};
  static const _checkinRoles = {'owner', 'admin', 'member', 'viewer'};
  bool get hasOps => _opsRoles.contains(role);
  bool get hasCheckin => _checkinRoles.contains(role);
  bool get isAgent => role == 'agent';
  bool get canActOnStations => hasOps && role != 'executive';
}

class EventItem {
  final String id, name, venue;
  final String? county, constituency, ward;
  final bool active, regionRestricted, listOnly;
  final int checkins, unique, outOfRegion;

  EventItem.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        name = j['name'],
        venue = j['venue'] ?? '',
        county = _s(j['county']),
        constituency = _s(j['constituency']),
        ward = _s(j['ward']),
        active = j['active'] ?? false,
        regionRestricted = j['region_restricted'] ?? false,
        listOnly = j['list_only'] ?? false,
        checkins = _i(j['checkins']),
        unique = _i(j['unique']),
        outOfRegion = _i(j['out_of_region']);

  String get area => [ward ?? constituency ?? county, venue].whereType<String>().where((s) => s.isNotEmpty).join(' · ');
}

class Drive {
  final String id, name;
  final String? county, constituency, ward, targetDate;
  final int target, mobilized, remaining;
  final double progress;
  final bool active;

  final Map<String, dynamic> raw;

  /// Progress after one more registration, shown while it waits to sync.
  Drive bumped() {
    final m = mobilized + 1;
    return Drive.fromJson({
      ...raw,
      'mobilized': m,
      'remaining': (target - m).clamp(0, target),
      'progress': target == 0 ? 0 : (m / target).clamp(0, 1),
    });
  }

  Drive.fromJson(Map<String, dynamic> j)
      : raw = j,
        id = j['id'],
        name = j['name'],
        county = _s(j['county']),
        constituency = _s(j['constituency']),
        ward = _s(j['ward']),
        targetDate = _s(j['target_date']),
        target = _i(j['target']),
        mobilized = _i(j['mobilized']),
        remaining = _i(j['remaining']),
        progress = _d(j['progress']),
        active = j['active'] ?? false;

  String get area => [county, constituency, ward].whereType<String>().join(' · ');
}

class Voter {
  final String nationalId, name, sex, dob, county, constituency, ward;
  final int age;
  final String? pollingCenter;

  Voter.fromJson(Map<String, dynamic> j)
      : nationalId = j['national_id'],
        name = j['name'],
        sex = j['sex'],
        dob = j['dob'],
        age = _i(j['age']),
        county = j['county'],
        constituency = j['constituency'],
        ward = j['ward'],
        pollingCenter = _s(j['polling_center']);
}

class Prior {
  final DateTime at;
  final String by;
  final String? where;

  /// Something this phone recorded itself (offline duplicate warning).
  Prior.local(this.at, {this.where}) : by = 'this phone';

  Prior.fromJson(Map<String, dynamic> j)
      : at = DateTime.parse(j['at']).toLocal(),
        by = j['by'],
        where = _s(j['where']);
}

class Lookup {
  /// ready | already_checked_in | not_on_list | already_mobilized
  final String status;
  final Voter? voter;
  final bool inRegion;
  final Prior? previous;

  /// No signal: the register can't be checked; [previous] is set if this phone already recorded the ID.
  Lookup.offline({this.previous, String? status})
      : status = status ?? 'offline',
        voter = null,
        inRegion = true;

  bool get isOffline => status == 'offline';

  Lookup.fromJson(Map<String, dynamic> j)
      : status = j['status'],
        voter = j['voter'] == null ? null : Voter.fromJson(j['voter']),
        inRegion = j['in_region'] ?? true,
        previous = j['previous'] == null ? null : Prior.fromJson(j['previous']);
}

class PersonRecord {
  final String id, nationalId, name, county, constituency, ward, by, groupName;
  final bool? inRegion;
  final DateTime at;

  PersonRecord.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        nationalId = j['national_id'],
        name = j['name'],
        county = j['county'],
        constituency = j['constituency'],
        ward = j['ward'],
        by = j['by'],
        groupName = j['group_name'],
        inRegion = j['in_region'] as bool?,
        at = DateTime.parse(j['at']).toLocal();
}

class FeedItem {
  final String kind, name, nationalId, group, by;
  final DateTime at;
  FeedItem.fromJson(Map<String, dynamic> j)
      : kind = j['kind'],
        name = j['name'],
        nationalId = j['national_id'],
        group = j['group'],
        by = j['by'],
        at = DateTime.parse(j['at']).toLocal();
  bool get isCheckin => kind == 'checkin';
}

class HomeData {
  final int myCheckinsToday, myMobilizedToday, orgCheckinsToday, orgMobilizedToday;
  final List<FeedItem> feed;
  HomeData.fromJson(Map<String, dynamic> j)
      : myCheckinsToday = _i(j['my_checkins_today']),
        myMobilizedToday = _i(j['my_mobilized_today']),
        orgCheckinsToday = _i(j['org_checkins_today']),
        orgMobilizedToday = _i(j['org_mobilized_today']),
        feed = [for (final f in j['feed'] as List) FeedItem.fromJson(f)];
}

class NameCount {
  final String name;
  final int count;
  NameCount.fromJson(Map<String, dynamic> j)
      : name = j['name'],
        count = _i(j['count']);
}

class CheckinInsights {
  final String day;
  final int total, unique, female, male;
  final double inRegionRate;
  final int? peakHour;
  final List<MapEntry<int, int>> byHour;

  CheckinInsights.fromJson(Map<String, dynamic> j)
      : day = j['day'],
        total = _i(j['total']),
        unique = _i(j['unique']),
        female = _i(j['female']),
        male = _i(j['male']),
        inRegionRate = _d(j['in_region_rate']),
        peakHour = (j['peak_hour'] as num?)?.toInt(),
        byHour = [for (final h in j['by_hour'] as List) MapEntry(_i(h['hour']), _i(h['count']))];
}

class MobilizationInsights {
  final Drive drive;
  final int today;
  final List<NameCount> topMobilizers;
  final String? paceStatus;

  MobilizationInsights.fromJson(Map<String, dynamic> j)
      : drive = Drive.fromJson(j['drive']),
        today = _i(j['today']),
        topMobilizers = [for (final m in j['top_mobilizers'] as List) NameCount.fromJson(m)],
        paceStatus = (j['pace'] as Map?)?['status'];
}
