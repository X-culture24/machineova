// Screenshots of the Checkin app for the SDICS clerks' training manual.
// Real screens from lib/, a fake server with SAMPLE data, a 360x780 phone.
// Run: flutter test test/manual_shots_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';

import 'package:checkin_mobile/api/client.dart';
import 'package:checkin_mobile/api/models.dart';
import 'package:checkin_mobile/screens/lock_screen.dart';
import 'package:checkin_mobile/screens/login.dart';
import 'package:checkin_mobile/screens/onboarding.dart';
import 'package:checkin_mobile/screens/shell.dart';
import 'package:checkin_mobile/session.dart';
import 'package:checkin_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

const flutterFonts = '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts';

Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    l.addFont(Future.value(ByteData.view(Uint8List.fromList(File(f).readAsBytesSync()).buffer)));
  }
  await l.load();
}

String today(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m).toUtc().toIso8601String();
}

// ---- SAMPLE data (made-up people) ----
final meJson = {
  'id': 'u1', 'name': 'Amina Wanjiru', 'email': 'amina.clerk@example.org', 'role': 'member',
  'module_events': true, 'module_mobilization': true, 'scope_label': 'Kibra',
  'organization': {'name': 'Sample Organization', 'active': true},
};
final events = [
  {'id': 'e1', 'name': 'Kibra Unity Rally', 'venue': 'Kamkunji Grounds', 'county': 'Nairobi', 'constituency': 'Kibra',
   'ward': 'Lindi', 'active': true, 'checkins': 312, 'unique': 298, 'out_of_region': 41},
  {'id': 'e2', 'name': 'Lindi Ward Meeting', 'venue': 'Lindi Social Hall', 'county': 'Nairobi', 'constituency': 'Kibra',
   'ward': 'Lindi', 'active': true, 'checkins': 86, 'unique': 80, 'out_of_region': 5},
];
final drive = {
  'id': 'd1', 'name': 'Langata Door-to-Door', 'county': 'Nairobi', 'constituency': 'Langata', 'ward': 'Nyayo Highrise',
  'target': 5000, 'mobilized': 2340, 'remaining': 2660, 'progress': 0.468, 'active': true,
};
Map<String, dynamic> voter(String id, String name, String sex, int age,
        {String county = 'Nairobi', String cons = 'Kibra', String ward = 'Lindi', String pc = 'Olympic Primary School', Map? home}) =>
    {
      'national_id': id, 'name': name, 'sex': sex, 'dob': '${2026 - age}-03-14', 'age': age, 'county': county,
      'constituency': cons, 'ward': ward, 'polling_center': pc, 'registered_on': '2017-02-10', 'source': 'voter_register',
      if (home != null) 'home': home,
    };
final people = [
  {'id': 'p1', 'national_id': '28651234', 'name': 'Joseph Kamau', 'county': 'Nairobi', 'constituency': 'Kibra',
   'ward': 'Lindi', 'by': 'Amina Wanjiru', 'group_name': 'Kibra Unity Rally', 'in_region': true, 'at': today(10, 24)},
  {'id': 'p2', 'national_id': '31902887', 'name': 'Peter Otieno', 'county': 'Kisumu', 'constituency': 'Kisumu Central',
   'ward': 'Kondele', 'by': 'Amina Wanjiru', 'group_name': 'Kibra Unity Rally', 'in_region': false, 'at': today(10, 11)},
  {'id': 'p3', 'national_id': '24418890', 'name': 'Grace Achieng', 'county': 'Nairobi', 'constituency': 'Kibra',
   'ward': 'Lindi', 'by': 'Amina Wanjiru', 'group_name': 'Kibra Unity Rally', 'in_region': true, 'at': today(9, 58)},
  {'id': 'p4', 'national_id': '30077123', 'name': 'Mary Njeri', 'county': 'Nairobi', 'constituency': 'Kibra',
   'ward': 'Lindi', 'by': 'Amina Wanjiru', 'group_name': 'Kibra Unity Rally', 'in_region': true, 'at': today(9, 40)},
];

class FakeServer {
  bool down = false;
  final sent = <String>[];

  Future<http.Response> handle(http.Request r) async {
    if (down) throw http.ClientException('SocketException: no signal');
    final p = r.url.path;
    final q = r.url.queryParameters;
    Object? body;
    if (r.method == 'POST') sent.add('$p ${r.body}');
    switch (p) {
      case '/api/me':
        body = meJson;
      case '/api/home':
        body = {
          'my_checkins_today': 48, 'my_mobilized_today': 12, 'org_checkins_today': 312, 'org_mobilized_today': 128,
          'feed': [
            {'kind': 'checkin', 'name': 'Joseph Kamau', 'national_id': '28651234', 'group': 'Kibra Unity Rally', 'by': 'You', 'at': today(10, 24)},
            {'kind': 'mobilization', 'name': 'Grace Achieng', 'national_id': '24418890', 'group': 'Langata Door-to-Door', 'by': 'You', 'at': today(10, 11)},
            {'kind': 'checkin', 'name': 'Peter Otieno', 'national_id': '31902887', 'group': 'Kibra Unity Rally', 'by': 'Brian O.', 'at': today(9, 58)},
            {'kind': 'mobilization', 'name': 'Mary Njeri', 'national_id': '30077123', 'group': 'Langata Door-to-Door', 'by': 'You', 'at': today(9, 40)},
          ],
        };
      case '/api/events':
        body = {'items': events};
      case '/api/drives':
        body = {'items': [drive]};
      case '/api/drives/d1':
        body = {'drive': {...drive, 'mobilized': 2341, 'remaining': 2659, 'progress': 0.468}};
      case '/api/checkins/lookup':
        final id = q['national_id']!.replaceAll(' ', '');
        if (id == '31902887') {
          body = {'status': 'ready', 'in_region': false,
            'voter': voter(id, 'Peter Otieno', 'M', 38, county: 'Kisumu', cons: 'Kisumu Central', ward: 'Kondele',
                pc: 'Kondele Primary School', home: {'county': 'Siaya', 'sub_county': 'Bondo', 'location': 'Sakwa Central', 'village': 'Sirongo'})};
        } else if (id == '24418890') {
          body = {'status': 'already_checked_in', 'in_region': true, 'voter': voter(id, 'Grace Achieng', 'F', 29),
            'previous': {'at': today(9, 58), 'by': 'Brian O.'}};
        } else {
          body = {'status': 'ready', 'in_region': true, 'voter': voter(id, 'Joseph Kamau', 'M', 34)};
        }
      case '/api/checkins':
        body = r.method == 'POST' ? {'in_region': true} : people;
      case '/api/mobilizations/lookup':
        body = {'status': 'ready', 'in_region': true,
          'voter': voter('30077123', 'Mary Njeri', 'F', 26, cons: 'Langata', ward: 'Nyayo Highrise', pc: 'Langata High School')};
      case '/api/mobilizations':
        body = r.method == 'POST' ? {'ok': true} : people.reversed.toList();
      case '/api/insights/checkins':
        body = {'day': DateTime.now().toIso8601String().substring(0, 10), 'total': 312, 'unique': 298, 'female': 168,
          'male': 144, 'in_region_rate': 0.86, 'peak_hour': 11,
          'by_hour': [for (final e in {8: 6, 9: 22, 10: 48, 11: 71, 12: 64, 13: 45, 14: 30, 15: 17, 16: 9}.entries) {'hour': e.key, 'count': e.value}]};
      case '/api/insights/mobilization':
        body = {'drive': drive, 'today': 128, 'pace': {'status': 'on_track'},
          'top_mobilizers': [{'name': 'Amina Wanjiru', 'count': 612}, {'name': 'Brian Odhiambo', 'count': 484},
            {'name': 'Faith Mueni', 'count': 391}, {'name': 'Samuel Kiptoo', 'count': 277}]};
      default:
        body = {};
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

void main() {
  final server = FakeServer();
  final rects = <String, Map<String, List<double>>>{};
  final rf = File('test/shots/rects.json');
  if (rf.existsSync()) {
    (jsonDecode(rf.readAsStringSync()) as Map<String, dynamic>).forEach((k, v) =>
        rects[k] = {for (final e in (v as Map<String, dynamic>).entries) e.key: [for (final x in e.value as List) (x as num).toDouble()]});
  }
  var debugCount = 0;

  setUpAll(() async {
    await loadFont('Lexend', [for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Lexend-$w.ttf']);
    await loadFont('MaterialIcons', ['$flutterFonts/MaterialIcons-Regular.otf']);
    await loadFont('Roboto', ['$flutterFonts/Roboto-Regular.ttf', '$flutterFonts/Roboto-Medium.ttf', '$flutterFonts/Roboto-Bold.ttf']);
    await loadFont('ArialUnicode', ['/System/Library/Fonts/Supplemental/Arial Unicode.ttf']);
    await loadFont('AppleEmoji', ['/System/Library/Fonts/Apple Color Emoji.ttc']);
    await initializeDateFormatting();
    httpClientFactory = () => MockClient(server.handle);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    server.down = false;
  });

  Future<void> settle(WidgetTester t, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await t.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> waitFor(WidgetTester t, Finder f, [int tries = 60]) async {
    for (var i = 0; i < tries && !t.any(f); i++) {
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await t.pump(const Duration(milliseconds: 150));
    }
    await t.pump(const Duration(milliseconds: 300));
    if (!t.any(f)) {
      debugCount++;
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('debug/miss_$debugCount.png'));
      // ignore: avoid_print
      print('WAIT MISS $debugCount: $f');
    }
  }

  Future<void> precache(WidgetTester t) async {
    await t.runAsync(() async {
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await t.pump();
  }

  Future<void> shot(WidgetTester t, String name, [Map<String, Finder> marks = const {}]) async {
    await precache(t);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    final m = <String, List<double>>{};
    marks.forEach((k, f) {
      if (t.any(f)) {
        final r = t.getRect(f.first);
        m[k] = [r.left * 2, r.top * 2, r.right * 2, r.bottom * 2];
      } else {
        m[k] = [];
      }
    });
    rects[name] = m;
    File('test/shots/rects.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));
  }

  Future<void> phone(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(720, 1560);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: home));
    await settle(t);
  }

  void signedIn() {
    session.me = Me.fromJson(meJson);
    session.restoring = false;
    api.userId = 'u1';
  }

  testWidgets('01 onboarding', (t) async {
    await phone(t, OnboardingScreen(onDone: () {}));
    await shot(t, '01_onboarding', {'1': find.text('Skip'), '2': find.text('Next')});
  });

  testWidgets('02 sign in', (t) async {
    session.me = null;
    await phone(t, const LoginScreen());
    await shot(t, '02_login', {
      '1': find.widgetWithText(TextField, 'Email or user ID'),
      '2': find.widgetWithText(TextField, 'Password'),
      '3': find.widgetWithText(FilledButton, 'Sign in'),
      '4': find.text('Forgot password?'),
    });
  });

  testWidgets('03 set PIN, 04 lock', (t) async {
    signedIn();
    await phone(t, const SetPinScreen());
    await shot(t, '03_set_pin', {'1': find.text('Set an app PIN')});
    await phone(t, const LockScreen());
    await shot(t, '04_lock', {'1': find.text('Enter your PIN'), '2': find.text('Forgot PIN?')});
  });

  testWidgets('05..12 home, check in', (t) async {
    signedIn();
    await phone(t, const Shell());
    await shot(t, '05_home', {
      '1': find.textContaining('Field Agent'),
      '2': find.text('TEAM CHECK-INS TODAY'),
      '3': find.text('Recent activity'),
      '4': find.byKey(const Key('start-action')),
      '5': find.byType(BottomAppBar),
    });
    await t.tap(find.byKey(const Key('start-action')));
    await settle(t);
    await shot(t, '06_choose', {'1': find.descendant(of: find.byType(BottomSheet), matching: find.text('Check in')), '2': find.descendant(of: find.byType(BottomSheet), matching: find.text('Mobilize'))});
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Check in')));
    await settle(t, 4);
    await waitFor(t, find.textContaining('Choose your event'));
    await t.tap(find.textContaining('Choose your event'));
    await settle(t);
    await shot(t, '07_pick_event', {'1': find.text('Kibra Unity Rally')});
    await t.tap(find.text('Kibra Unity Rally').last);
    await settle(t);
    await t.enterText(find.byKey(const Key('id-input')), '28651234');
    await settle(t, 2);
    await shot(t, '08_find', {
      '1': find.text('Kibra Unity Rally'),
      '2': find.text('Scan ID card'),
      '3': find.byKey(const Key('id-input')),
      '4': find.byKey(const Key('lookup')),
    });
    await t.tap(find.byKey(const Key('lookup')));
    await settle(t, 10);
    await t.drag(find.byType(ListView).last, const Offset(0, -260));
    await settle(t, 2);
    await shot(t, '09_confirm', {
      '1': find.text('Joseph Kamau'),
      '2': find.widgetWithText(TextFormField, 'Phone'),
      '3': find.widgetWithText(FilledButton, 'Check in'),
    });
    await t.tap(find.widgetWithText(FilledButton, 'Check in'));
    await settle(t, 6);
    await shot(t, '10_done', {'1': find.byType(SnackBar)});
    await settle(t, 20);

    // Out-of-area voter
    await t.enterText(find.byKey(const Key('id-input')), '31902887');
    await t.tap(find.byKey(const Key('lookup')));
    await settle(t, 10);
    await t.drag(find.byType(ListView).last, const Offset(0, -420));
    await settle(t, 2);
    await shot(t, '11_out_of_area', {'1': find.text('Outside this area')});

    // Already checked in
    await t.drag(find.byType(ListView).last, const Offset(0, 900));
    await settle(t, 2);
    await t.enterText(find.byKey(const Key('id-input')), '24418890');
    await t.tap(find.byKey(const Key('lookup')));
    await settle(t, 10);
    await shot(t, '12_already', {'1': find.textContaining('Already checked in today'), '2': find.text('Next voter')});
  });

  testWidgets('13 mobilize', (t) async {
    signedIn();
    await phone(t, const Shell());
    await t.tap(find.byKey(const Key('start-action')));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Mobilize')));
    await settle(t, 4);
    await waitFor(t, find.byKey(const Key('id-input')));
    await t.enterText(find.byKey(const Key('id-input')), '30077123');
    await t.tap(find.byKey(const Key('lookup')));
    await waitFor(t, find.text('Voter details'));
    await shot(t, '13_mobilize', {
      '1': find.text('Langata Door-to-Door'),
      '2': find.byKey(const Key('id-input')),
      '3': find.text('Voter details'),
    });
    await t.drag(find.byType(ListView).last, const Offset(0, -700));
    await settle(t, 2);
    await shot(t, '14_mobilize_register', {'1': find.widgetWithText(FilledButton, 'Register')});
  });

  testWidgets('15..18 insights, people, account', (t) async {
    signedIn();
    await phone(t, const Shell());
    await t.tap(find.byKey(const Key('tab-Insights')));
    await waitFor(t, find.text('TOTAL CHECK-INS'));
    await shot(t, '15_insights_checkins', {
      '1': find.text('Check-ins').first,
      '2': find.text('TOTAL CHECK-INS'),
      '3': find.text('Check-ins by hour'),
    });
    await t.tap(find.text('Mobilization'));
    await waitFor(t, find.text('Top mobilizers'));
    await shot(t, '16_insights_mobilization', {
      '1': find.text('Mobilization'),
      '2': find.text('VOTERS MOBILIZED'),
      '3': find.text('Top mobilizers'),
    });
    await t.tap(find.byKey(const Key('tab-People')));
    await waitFor(t, find.text('Joseph Kamau'));
    await shot(t, '17_people', {
      '1': find.text('Check-ins').first,
      '2': find.text('All events'),
      '3': find.widgetWithText(TextField, 'Search name or ID number'),
      '4': find.text('Joseph Kamau'),
    });
    await t.tap(find.byKey(const Key('tab-Account')));
    await settle(t, 6);
    await shot(t, '18_account', {
      '1': find.text('Change password'),
      '2': find.text('Sync & offline data'),
      '3': find.text('Sign out'),
    });
  });

  testWidgets('19 offline check-in', (t) async {
    signedIn();
    await phone(t, const Shell());
    await t.tap(find.byKey(const Key('start-action')));
    await settle(t);
    await t.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text('Check in')));
    await settle(t, 4);
    await waitFor(t, find.textContaining('Choose your event'));
    await t.tap(find.textContaining('Choose your event'));
    await settle(t);
    await t.tap(find.text('Kibra Unity Rally').last);
    await settle(t);
    server.down = true;
    await t.enterText(find.byKey(const Key('id-input')), '33445566');
    await t.tap(find.byKey(const Key('lookup')));
    await settle(t, 10);
    await shot(t, '19_offline', {
      '1': find.textContaining('Offline'),
      '2': find.textContaining("can't check the register"),
    });
  });
}
