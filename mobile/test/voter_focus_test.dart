// The dashboard's voter-focused pages in the app, with a fake server: turnout, polling stations,
// participant filter, event picker and admission. Screenshots: flutter test --update-goldens test/voter_focus_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:checkin_mobile/api/client.dart';
import 'package:checkin_mobile/api/models.dart';
import 'package:checkin_mobile/screens/checkin.dart';
import 'package:checkin_mobile/screens/insights.dart';
import 'package:checkin_mobile/screens/people.dart';
import 'package:checkin_mobile/screens/turnout.dart';
import 'package:checkin_mobile/session.dart';
import 'package:checkin_mobile/theme.dart';
import 'package:checkin_mobile/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await l.load();
}

void main() {
  final asked = <Uri>[];
  Map<String, dynamic> ev(int n) => {
        'id': 'e$n', 'name': n == 1 ? 'Kabarnet members forum' : 'Forum $n', 'venue': 'Hall $n', 'county': 'Baringo',
        'constituency': 'Baringo Central', 'ward': 'Kabarnet', 'coverage_level': 'county', 'polling_station_code': null,
        'starts_at': '2026-11-24T06:00:00Z', 'active': true, 'list_only': n == 1, 'region_restricted': n == 1,
        'checkins': 130, 'unique': 120, 'out_of_region': 13,
      };
  Map<String, dynamic> row(String a, int reached, int reg, String st) =>
      {'area': a, 'reached': reached, 'registered': reg, 'remaining': reg - reached, 'coverage': 0, 'status': st};
  Map<String, dynamic> person(String id, bool selected) => {
        'id': id, 'national_id': '2345678$id', 'name': 'Grace Sample $id', 'phone': '0712345678', 'county': 'Baringo',
        'constituency': 'Baringo Central', 'ward': 'Kabarnet', 'by': 'Tom Agent', 'group_name': 'Kabarnet members forum',
        'in_region': true, 'selected_participant': selected, 'at': '2026-11-24T08:00:00Z',
      };

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await loadFont('Lexend', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Lexend-$w.ttf']);
    await loadFont('MaterialIcons',
        ['${Platform.environment['HOME']}/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    httpClientFactory = () => MockClient((r) async {
          asked.add(r.url);
          final q = r.url.queryParameters;
          final Object body;
          switch (r.url.path) {
            case '/api/events':
              body = {'summary': {}, 'items': [for (var n = 1; n <= 7; n++) ev(n)]};
            case '/api/insights/checkins':
              body = {'day': '2026-11-24', 'total': 130, 'unique': 120, 'female': 70, 'male': 60, 'in_region_rate': .9,
                'peak_hour': 10, 'by_hour': [for (var h = 8; h < 14; h++) {'hour': h, 'count': h == 10 ? 50 : 16}]};
            case '/api/insights/coverage':
              final level = q['ward'] != null ? 'polling_center' : q['constituency'] != null ? 'ward' : 'constituency';
              body = {
                'level': level, 'label': q['ward'] ?? q['constituency'] ?? 'Baringo', 'reached': 112, 'registered': 281053,
                'remaining': 280941, 'not_registered': 8, 'female': 64, 'male': 56, 'top_age_group': '35–44',
                'rows': level == 'constituency'
                    ? [row('Baringo Central', 100, 60000, 'critical'), row('Mogotio', 12, 40000, 'critical')]
                    : level == 'ward' ? [row('Kabarnet', 90, 15000, 'critical')] : null,
                'push_here_next': [row('Mogotio', 12, 40000, 'critical')],
              };
            case '/api/events/e1/station-coverage':
              body = [
                {'code': 'sdics-1', 'name': 'Kabarnet Primary', 'county': 'Baringo', 'constituency': 'Baringo Central', 'ward': 'Kabarnet', 'registered': 900, 'reached': 45},
                {'code': 'sdics-2', 'name': 'Mogotio Primary', 'county': 'Baringo', 'constituency': 'Mogotio', 'ward': 'Mogotio', 'registered': 700, 'reached': 0},
              ];
            case '/api/checkins':
              body = [for (final s in [true, false]) if (q['participants'] == null || (q['participants'] == 'selected') == s) person(s ? '1' : '2', s)];
            case '/api/checkins/lookup':
              body = {'status': 'not_on_list', 'in_region': true};
            default:
              return http.Response('{"error":"not faked"}', 404);
          }
          return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
        });
    session.me = Me.fromJson({
      'id': 'u1', 'name': 'Tom Agent', 'email': 'a@test', 'role': 'member', 'module_events': true,
      'organization': {'name': 'SDICS Members', 'active': true, 'vocabulary': 'sdics_chiefs'}, 'scope_label': 'Baringo',
    });
  });

  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 4; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await t.pump(const Duration(milliseconds: 400));
    }
    await t.pumpAndSettle();
  }

  Future<void> open(WidgetTester t, Widget w, {double height = 2340}) async {
    t.view.physicalSize = Size(1080, height);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: w));
    await settle(t);
  }

  test('turnout keeps two decimals, as the dashboard', () {
    expect(fmtTurnout(0, 0), '—');
    expect(fmtTurnout(0, 100), '0%');
    expect(fmtTurnout(1, 1000000), '<0.01%');
    expect(fmtTurnout(45, 900), '5%');
    expect(fmtTurnout(1, 300), '0.33%');
  });

  // One test: the app's client, vault and cache are global and live for the process.
  testWidgets('turnout, stations, people and check-in', (t) async {
    await open(t, const InsightsScreen(), height: 5600);
    expect(find.text('Voter turnout · Baringo'), findsOneWidget);
    expect(find.text('0.04%'), findsOneWidget);
    expect(find.textContaining('Push here next: Mogotio'), findsOneWidget);
    expect(find.text('10% of check-ins'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/voter-insights.png'));

    // Constituency → ward → polling centre, and back up.
    await t.tap(find.text('Baringo Central'));
    await settle(t);
    expect(find.text('By ward'), findsOneWidget);
    await t.tap(find.text('Kabarnet'));
    await settle(t);
    expect(find.text('By polling centre'), findsOneWidget);
    expect(asked.last.queryParameters, containsPair('constituency', 'Baringo Central'));
    expect(find.text('No registered voters found for this area.'), findsOneWidget, reason: 'null rows');
    await t.tap(find.byKey(const Key('turnout-up')));
    await settle(t);
    expect(find.text('By ward'), findsOneWidget);

    // The event picker searches once there are more than a few events.
    await t.tap(find.text('EVENT · TAP TO SWITCH'));
    await settle(t);
    await t.enterText(find.byKey(const Key('event-search')), 'forum 5');
    await settle(t);
    await t.tap(find.text('Forum 5'));
    await settle(t);
    expect(find.text('Forum 5'), findsOneWidget);
    expect(asked.any((u) => u.path == '/api/insights/coverage' && u.queryParameters['event_id'] == 'e5'), isTrue);

    await t.pumpWidget(const SizedBox());
    await open(t, StationTurnoutScreen(event: EventItem.fromJson(ev(1))));
    expect(find.text('2.81%'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/voter-stations.png'));
    await t.tap(find.byKey(const Key('stations-zero')));
    await settle(t);
    expect(find.text('Mogotio Primary'), findsOneWidget);
    expect(find.text('Kabarnet Primary'), findsNothing);
    await t.enterText(find.byKey(const Key('station-search')), 'nowhere');
    await settle(t);
    expect(find.text('No polling stations match.'), findsOneWidget);

    await t.pumpWidget(const SizedBox());
    await open(t, const PeopleScreen());
    expect(find.text('Members checked in'), findsOneWidget);
    expect(find.textContaining('· General'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/voter-people.png'));
    await t.tap(find.byKey(const Key('participants-selected')));
    await settle(t);
    expect(find.text('Grace Sample 1'), findsOneWidget);
    expect(find.text('Grace Sample 2'), findsNothing);

    await t.pumpWidget(const SizedBox());
    await open(t, const CheckinFlow());
    await t.tap(find.text('EVENT · TAP TO SWITCH'));
    await settle(t);
    await t.tap(find.text('Kabarnet members forum'));
    await settle(t);
    expect(find.text('SELECTED PARTICIPANTS ONLY'), findsOneWidget);
    expect(find.text('Find a voter'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/voter-checkin.png'));
    await t.enterText(find.byKey(const Key('id-input')), '23456789');
    await t.ensureVisible(find.byKey(const Key('lookup')));
    await t.tap(find.byKey(const Key('lookup')));
    await settle(t);
    expect(find.textContaining('Not on the participant list'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
