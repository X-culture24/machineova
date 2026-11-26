// Models mirroring the Checkin Go API JSON.

String? _s(dynamic v) => v as String?;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;

class Me {
  final String id, name, email, role;
  final bool moduleEvents, moduleMobilization;
  final String? orgName;
  final bool orgActive;

  /// The organization's wording: 'standard' or 'sdics_chiefs' (see terms.dart).
  final String vocabulary;
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
        vocabulary = (j['organization'] as Map?)?['vocabulary'] ?? 'standard',
        scopeLabel = j['scope_label'] ?? '';

  bool get canOperate => role != 'viewer';

  static const _opsRoles = {'owner', 'executive', 'admin', 'chief_agent', 'manager', 'agent'};
  static const _checkinRoles = {'owner', 'admin', 'member', 'viewer'};
  bool get hasOps => _opsRoles.contains(role);
  bool get hasCheckin => _checkinRoles.contains(role) || isFieldAgent;

  /// The field app is for field agents only: election agents and Checkin field members.
  /// Owners, admins, managers and candidates use the web dashboard.
  bool get isFieldAgent => role == 'agent' || role == 'member';
  bool get isAgent => role == 'agent';
  bool get canActOnStations => hasOps && role != 'executive';
}

class EventItem {
  final String id, name, venue;
  final String? county, constituency, ward;
  final bool active, regionRestricted, listOnly;
  final int checkins, unique, outOfRegion;

  /// Vying level whose registered voters the turnout is measured against (null: the event's own area).
  final String? coverageLevel;

  /// The venue's polling station, when one was chosen.
  final String? pollingStation;
  final DateTime? startsAt;

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
        outOfRegion = _i(j['out_of_region']),
        coverageLevel = _s(j['coverage_level']),
        pollingStation = _s(j['polling_station_code']),
        startsAt = j['starts_at'] == null ? null : DateTime.parse(j['starts_at']).toLocal();

  /// Who may check in, in the dashboard's words.
  String get admission => listOnly ? 'Selected participants only' : 'General participants';

  /// The area whose registered voters count towards this event's turnout.
  String get vyingArea {
    switch (coverageLevel) {
      case 'national':
        return 'National';
      case 'county':
        return county ?? '';
      case 'constituency':
        return constituency ?? '';
      case 'ward':
        return ward ?? '';
    }
    return ward ?? constituency ?? county ?? 'National';
  }

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty ||
        [name, venue, county, constituency, ward].any((p) => p != null && p.toLowerCase().contains(q));
  }

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

/// Where a person comes from per their national ID record.
class HomeArea {
  final String? county, subCounty, division, location, subLocation, village;
  HomeArea.fromJson(Map<String, dynamic> j)
      : county = _s(j['county']),
        subCounty = _s(j['sub_county']),
        division = _s(j['division']),
        location = _s(j['location']),
        subLocation = _s(j['sub_location']),
        village = _s(j['village']);

  /// Smallest place first: "Village, Sub-location, Location, Sub-county, County".
  String get line => [village, subLocation, location, subCounty, county]
      .whereType<String>()
      .where((p) => p.isNotEmpty)
      .fold<List<String>>([], (acc, p) => acc.contains(p) ? acc : (acc..add(p)))
      .join(', ');
}

class Voter {
  final String nationalId, name, sex, dob, county, constituency, ward;
  final int age;
  final String? pollingCenter;

  /// Which reference resolved the ID: 'voter_register' or 'id_registry' (national ID records).
  final String source;

  /// Voter registration date (YYYY-MM-DD), registered voters only.
  final String? registeredOn;

  /// Home area from the national ID record (null when the ID records don't know them).
  final HomeArea? home;

  Voter.fromJson(Map<String, dynamic> j)
      : nationalId = j['national_id'],
        name = j['name'] ?? '',
        sex = j['sex'] ?? '',
        dob = j['dob'] ?? '',
        age = _i(j['age']),
        county = j['county'] ?? '',
        constituency = j['constituency'] ?? '',
        ward = j['ward'] ?? '',
        pollingCenter = _s(j['polling_center']),
        source = j['source'] ?? 'voter_register',
        registeredOn = _s(j['registered_on']),
        home = j['home'] == null ? null : HomeArea.fromJson(j['home']);

  /// Found, but the register lacks a name or sex (operator must fill them in).
  bool get missingIdentity => name.trim().isEmpty || (sex != 'F' && sex != 'M');

  /// Identity confirmed from national ID records, but not on the voter register.
  bool get idOnly => source == 'id_registry';

  String get sexLabel => sex == 'F' ? 'Female' : sex == 'M' ? 'Male' : 'Sex unknown';

  String get area => [county, constituency, ward].where((s) => s.isNotEmpty).join(' · ');
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
  final String? phone;
  final bool? inRegion;

  /// Check-ins only: sex (F/M or empty), age in years and its band (18–24 …, Unknown).
  final String sex;
  final int? age;
  final String? ageGroup;

  /// On the event's participant list (check-ins only).
  final bool? selectedParticipant;
  final DateTime at;

  PersonRecord.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        phone = _s(j['phone']),
        nationalId = j['national_id'],
        name = j['name'],
        county = j['county'],
        constituency = j['constituency'],
        ward = j['ward'],
        by = j['by'],
        groupName = j['group_name'],
        inRegion = j['in_region'] as bool?,
        selectedParticipant = j['selected_participant'] as bool?,
        sex = (j['sex'] as String?) ?? '',
        age = (j['age'] as num?)?.toInt(),
        ageGroup = j['age_group'] as String?,
        at = DateTime.parse(j['at']).toLocal();
}

/// One value a check-in filter can take, with how many check-ins have it.
class FacetValue {
  final String value, label;
  final int count;
  FacetValue.fromJson(Map<String, dynamic> j)
      : value = j['value'] as String,
        label = ((j['label'] as String?) ?? '').isEmpty ? j['value'] as String : j['label'] as String,
        count = (j['count'] as num).toInt();
}

/// Filters and sort for the check-in list; empty fields are not sent.
class CheckinQuery {
  final Map<String, String> filters; // sex, age_group, county, constituency, ward, region, home_county, by
  final String sort; // at, name, age, county, ward, …
  final bool descending;
  const CheckinQuery({this.filters = const {}, this.sort = 'at', this.descending = true});
  bool get isDefault => filters.isEmpty && sort == 'at' && descending;
  Map<String, String?> get params => {...filters, 'sort': sort, 'dir': descending ? 'desc' : 'asc'};
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

/// Registered voters reached in one area (county, constituency, ward or polling centre).
class CoverageRow {
  final String area, status;
  final int registered, reached, remaining;
  CoverageRow.fromJson(Map<String, dynamic> j)
      : area = j['area'] ?? '',
        status = j['status'] ?? 'not_started',
        registered = _i(j['registered']),
        reached = _i(j['reached']),
        remaining = _i(j['remaining']);

  static const _labels = {
    'strong': 'Strong',
    'moderate': 'Moderate',
    'low': 'Low',
    'critical': 'Critical',
    'not_started': 'Not started',
  };
  String get statusLabel => _labels[status] ?? status;
}

/// An event's turnout: people checked in against the registered voters of its vying area.
class Coverage {
  final String level, label;
  final int reached, registered, remaining, notRegistered, female, male;
  final String? topAgeGroup;
  final List<CoverageRow> rows, pushHereNext;

  Coverage.fromJson(Map<String, dynamic> j)
      : level = j['level'] ?? '',
        label = j['label'] ?? '',
        reached = _i(j['reached']),
        registered = _i(j['registered']),
        remaining = _i(j['remaining']),
        notRegistered = _i(j['not_registered']),
        female = _i(j['female']),
        male = _i(j['male']),
        topAgeGroup = _s(j['top_age_group']),
        rows = [for (final r in (j['rows'] as List?) ?? const []) CoverageRow.fromJson(r)],
        pushHereNext = [for (final r in (j['push_here_next'] as List?) ?? const []) CoverageRow.fromJson(r)];

  /// Constituencies open into wards, wards into polling centres (as on the dashboard).
  bool get canDrill => level == 'constituency' || level == 'ward';

  String get areaLabel =>
      const {
        'county': 'County',
        'constituency': 'Constituency',
        'ward': 'Ward',
        'polling_center': 'Polling centre',
      }[level] ??
      'Area';
}

class StationCoverage {
  final String code, name, county, constituency, ward;
  final int registered, reached;
  StationCoverage.fromJson(Map<String, dynamic> j)
      : code = j['code'] ?? '',
        name = j['name'] ?? '',
        county = j['county'] ?? '',
        constituency = j['constituency'] ?? '',
        ward = j['ward'] ?? '',
        registered = _i(j['registered']),
        reached = _i(j['reached']);

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    return q.isEmpty || [code, name, county, constituency, ward].any((p) => p.toLowerCase().contains(q));
  }
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


// ---- Problems reported (events, members' check-ins, the dashboard or app) ----
const issueCategories = <String, String>{
  'internet': 'Connectivity',
  'device': 'Device or equipment',
  'location': 'Venue, location or coverage',
  'account': 'Sign-in / PIN / account',
  'app': 'Check-in, dashboard or app',
  'other': 'Other',
};

class Issue {
  final String id, category, chiefName, nationalId, phone, location, description, actionTaken, status, reportedBy;
  final String? eventId, eventName;
  final DateTime reportedAt;

  Issue.fromJson(Map<String, dynamic> j)
      : id = j['id'],
        eventId = _s(j['event_id']),
        eventName = _s(j['event_name']),
        category = j['category'] ?? 'other',
        chiefName = j['chief_name'] ?? '',
        nationalId = j['national_id'] ?? '',
        phone = j['phone'] ?? '',
        location = j['location'] ?? '',
        description = j['description'] ?? '',
        actionTaken = j['action_taken'] ?? '',
        status = j['status'] ?? 'open',
        reportedBy = j['reported_by'] ?? '',
        reportedAt = DateTime.parse(j['reported_at']).toLocal();

  String get categoryLabel => issueCategories[category] ?? category;
  bool get open => status == 'open';
}
