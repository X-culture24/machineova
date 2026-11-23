// Field issues screens with a fake server: the list, the form, the chief look-up from a check-in,
// and what is sent. Also saves their screenshots: flutter test --update-goldens test/issues_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:checkin_mobile/api/client.dart';
import 'package:checkin_mobile/api/models.dart';
import 'package:checkin_mobile/screens/issues.dart';
import 'package:checkin_mobile/session.dart';
import 'package:checkin_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await l.load();
}

void main() {
  final posted = <Map<String, dynamic>>[];
  final issues = <Map<String, dynamic>>[
    {
      'id': 'i1', 'event_id': 'e1', 'event_name': 'Baringo chiefs training', 'category': 'internet',
      'chief_name': 'Grace Chepkoech', 'national_id': '23456789', 'phone': '0712345678', 'location': 'Kapropita, Kabarnet',
      'description': 'No data bundles on the phone; could not download the roll.', 'action_taken': 'Shared a hotspot.',
      'status': 'resolved', 'reported_by': 'Tom Trainer', 'reported_at': '2026-11-20T08:15:00Z',
    },
    {
      'id': 'i2', 'event_id': 'e1', 'event_name': 'Baringo chiefs training', 'category': 'location',
      'chief_name': 'Daniel Kiprono', 'national_id': '11112222', 'phone': '', 'location': 'Ewalel, Kabarnet',
      'description': 'SDICS has him in Kapropita; he is the chief of Ewalel.', 'action_taken': '',
      'status': 'open', 'reported_by': 'Tom Trainer', 'reported_at': '2026-11-20T09:02:00Z',
    },
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await loadFont('Lexend', [for (final w in [400, 500, 600, 700]) 'assets/fonts/Lexend-$w.ttf']);
    final home = Platform.environment['HOME'];
    await loadFont('MaterialIcons', ['$home/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    httpClientFactory = () => MockClient((r) async {
          final p = r.url.path;
          Object body;
          var status = 200;
          if (p == '/api/events') {
            body = {
              'summary': {},
              'items': [
                {'id': 'e1', 'name': 'Baringo chiefs training', 'venue': 'Kabarnet hall', 'county': 'Baringo', 'active': true},
                {'id': 'e2', 'name': 'Bomet chiefs training', 'venue': 'Bomet hall', 'county': 'Bomet', 'active': false},
              ],
            };
          } else if (p == '/api/issues' && r.method == 'GET') {
            body = {'items': issues};
          } else if (p == '/api/issues' && r.method == 'POST') {
            final b = jsonDecode(r.body) as Map<String, dynamic>;
            posted.add(b);
            body = {...b, 'id': 'new', 'event_name': 'Baringo chiefs training', 'reported_by': 'Tom Trainer', 'reported_at': '2026-11-20T10:00:00Z'};
            status = 201;
          } else if (p == '/api/issues/chief') {
            if (r.url.queryParameters['national_id'] == '30112233') {
              body = {'name': 'Mary Wanjiku', 'phone': '0722000111', 'location': 'Ewalel, Kabarnet, Baringo'};
            } else {
              body = {'error': 'Not checked in at this training'};
              status = 404;
            }
          } else {
            body = {'error': 'not faked: $p'};
            status = 404;
          }
          return http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});
        });
    session.me = Me.fromJson({
      'id': 'u1', 'name': 'Tom Trainer', 'email': 'trainer@test', 'role': 'member', 'module_events': true,
      'organization': {'name': 'SDICS Chiefs Training', 'active': true, 'vocabulary': 'sdics_chiefs'}, 'scope_label': 'All counties',
    });
  });

  testWidgets('list, record a problem with the chief from their check-in', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const IssuesScreen()));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('Chief location issue'), findsOneWidget);
    expect(find.text('OPEN'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/issues-list.png'));

    await t.tap(find.byKey(const Key('record-issue')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('Baringo chiefs training (open)'), findsOneWidget, reason: 'the open training is chosen');

    // Saving needs a kind of problem and a description.
    await t.scrollUntilVisible(find.byKey(const Key('issue-save')), 300, scrollable: find.byType(Scrollable).last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('issue-save')));
    await t.pumpAndSettle();
    expect(find.text('Pick the kind of problem.'), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('issue-cat-device')), -300, scrollable: find.byType(Scrollable).last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('issue-cat-device')));
    await t.enterText(find.byKey(const Key('issue-id')), '30112233');
    await t.tap(find.text('Find'));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pumpAndSettle();
    expect(find.text('Mary Wanjiku'), findsOneWidget, reason: 'filled from the check-in');
    expect(find.text('Filled from their check-in.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('issue-what')), 'Phone screen cracked; could not open SDICS Field.');
    await t.enterText(find.byKey(const Key('issue-action')), "Signed in on the trainer's spare phone.");
    await t.pumpAndSettle();
    await t.drag(find.byType(Scrollable).last, const Offset(0, 3000)); // back to the top
    await t.pumpAndSettle();
    await t.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/issues-form.png'));

    await t.scrollUntilVisible(find.byKey(const Key('issue-save')), 300, scrollable: find.byType(Scrollable).last);
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('issue-save')));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pumpAndSettle();
    expect(posted, hasLength(1));
    expect(posted.single, containsPair('event_id', 'e1'));
    expect(posted.single, containsPair('category', 'device'));
    expect(posted.single, containsPair('chief_name', 'Mary Wanjiku'));
    expect(posted.single, containsPair('phone', '0722000111'));
    expect(posted.single, containsPair('national_id', '30112233'));
    expect(posted.single, containsPair('status', 'open'));
    expect(find.text('Problem recorded.'), findsOneWidget);
    expect(find.text('Record a problem'), findsWidgets, reason: 'back on the list');
  });
}
