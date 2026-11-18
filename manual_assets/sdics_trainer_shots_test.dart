// Screenshots for the one-page SDICS trainer guide: mark a chief present and collect their phone.
// Real screens from lib/, a fake server with SAMPLE data (made-up chiefs), a 360x780 phone.
// Run from mobile/:  cp ../manual_assets/sdics_trainer_shots_test.dart test/ &&
//   flutter test test/sdics_trainer_shots_test.dart --update-goldens   (shots land in test/sdics/)
import 'dart:convert';
import 'dart:io';

import 'package:checkin_mobile/api/client.dart';
import 'package:checkin_mobile/api/models.dart';
import 'package:checkin_mobile/screens/login.dart';
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
  'id': 'u1', 'name': 'Faith Jepkosgei', 'email': 'trainer.nandi@example.org', 'role': 'member',
  'module_events': true, 'module_mobilization': false, 'scope_label': 'Nandi',
  'organization': {'name': 'SDICS Chiefs Training', 'active': true, 'vocabulary': 'sdics_chiefs'},
};
final training = {
  'id': 'e1', 'name': 'SDICS App Training – Chiefs – Nandi', 'venue': 'Kapsabet County Hall', 'county': 'Nandi',
  'constituency': null, 'ward': null, 'active': true, 'checkins': 47, 'unique': 47, 'out_of_region': 0,
};
Map<String, dynamic> voter(String id, String name, String sex, int age, String cons, String ward, String pc) => {
      'national_id': id, 'name': name, 'sex': sex, 'dob': '${2026 - age}-06-02', 'age': age, 'county': 'Nandi',
      'constituency': cons, 'ward': ward, 'polling_center': pc, 'registered_on': '2012-11-19', 'source': 'voter_register',
    };
Map<String, dynamic> present(String id, String nid, String name, String phone, String cons, String ward, int h, int m) => {
      'id': id, 'national_id': nid, 'name': name, 'sex': 'M', 'phone': phone, 'county': 'Nandi', 'constituency': cons,
      'ward': ward, 'by': 'Faith Jepkosgei', 'group_name': 'SDICS App Training – Chiefs – Nandi', 'in_region': true,
      'at': today(h, m),
    };
final presentList = [
  present('p1', '23456781', 'Kiprotich Arap Sang', '0712 345 678', 'Emgwen', 'Kapsabet', 9, 42),
  present('p2', '20981234', 'Wilson Kibet Rotich', '0722 901 334', 'Aldai', 'Kobujoi', 9, 37),
  present('p3', '25110987', 'Jane Chebet Kosgei', '0733 118 902', 'Mosop', 'Kabiyet', 9, 31),
  present('p4', '19876543', 'Samuel Kiplagat Tuwei', '0701 554 210', 'Chesumei', 'Kosirai', 9, 26),
  present('p5', '22334455', 'Esther Jerop Koech', '0745 660 781', 'Nandi Hills', 'Chepkunyuk', 9, 20),
  present('p6', '21447766', 'Paul Kipchumba Lagat', '0710 228 449', 'Tinderet', 'Songhor/Soba', 9, 14),
];

class FakeServer {
  Future<http.Response> handle(http.Request r) async {
    final p = r.url.path;
    Object? body;
    switch (p) {
      case '/api/me':
        body = meJson;
      case '/api/home':
        body = {
          'my_checkins_today': 18, 'my_mobilized_today': 0, 'org_checkins_today': 47, 'org_mobilized_today': 0,
          'feed': [
            for (final x in presentList.take(4))
              {'kind': 'checkin', 'name': x['name'], 'national_id': x['national_id'], 'group': 'Nandi training', 'by': 'You', 'at': x['at']},
          ],
        };
      case '/api/events':
        body = {'items': [training]};
      case '/api/checkins/lookup':
        body = {'status': 'ready', 'in_region': true, 'in_register': true, 'registered_voter': true,
          'voter': voter('23456781', 'Kiprotich Arap Sang', 'M', 52, 'Emgwen', 'Kapsabet', 'Kapsabet Boys High School')};
      case '/api/checkins':
        body = r.method == 'POST' ? {'in_region': true, 'name': 'Kiprotich Arap Sang'} : presentList;
      case '/api/insights/checkins':
        body = {'day': DateTime.now().toIso8601String().substring(0, 10), 'total': 47, 'unique': 47, 'female': 9,
          'male': 38, 'in_region_rate': 1.0, 'peak_hour': 9,
          'by_hour': [for (final e in {8: 11, 9: 29, 10: 7}.entries) {'hour': e.key, 'count': e.value}]};
      default:
        body = {};
    }
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json; charset=utf-8'});
  }
}

void main() {
  final server = FakeServer();
  final rects = <String, Map<String, List<double>>>{};

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
    expect(f, findsWidgets, reason: 'waiting for $f');
  }

  Future<void> shot(WidgetTester t, String name, [Map<String, Finder> marks = const {}]) async {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('sdics/$name.png'));
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
    Directory('test/sdics').createSync(recursive: true);
    File('test/sdics/rects.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));
  }

  Future<void> phone(WidgetTester t, Widget home) async {
    t.view.physicalSize = const Size(720, 1560);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    // The test fonts lack ✓; real phones have it. Fall back to Arial Unicode for screenshots.
    final th = buildTheme();
    const fb = ['ArialUnicode', 'AppleEmoji'];
    final theme = th.copyWith(
      textTheme: th.textTheme.apply(fontFamilyFallback: fb),
      snackBarTheme: th.snackBarTheme.copyWith(
          contentTextStyle: (th.snackBarTheme.contentTextStyle ?? const TextStyle(color: Colors.white))
              .copyWith(fontFamilyFallback: fb)),
    );
    await t.pumpWidget(MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: home));
    await settle(t);
  }

  void signedIn() {
    session.me = Me.fromJson(meJson);
    session.restoring = false;
    api.userId = 'u1';
  }

  testWidgets('1 sign in', (t) async {
    session.me = null;
    await phone(t, const LoginScreen());
    await t.enterText(find.widgetWithText(TextField, 'Email or user ID'), 'trainer.nandi@example.org');
    await settle(t, 2);
    await shot(t, '1_login', {
      '1': find.widgetWithText(TextField, 'Email or user ID'),
      '2': find.widgetWithText(TextField, 'Password'),
      '3': find.widgetWithText(FilledButton, 'Sign in'),
    });
  });

  testWidgets('2..6 home, find chief, phone, present, list', (t) async {
    signedIn();
    await phone(t, const Shell());
    await waitFor(t, find.text('Recent activity'));
    await shot(t, '2_home', {
      '1': find.text('Mark chief present').first,
      '2': find.byKey(const Key('start-action')),
    });

    await t.tap(find.byKey(const Key('start-action')));
    await settle(t, 4);
    await waitFor(t, find.byKey(const Key('id-input')));
    await t.enterText(find.byKey(const Key('id-input')), '23456781');
    await settle(t, 2);
    await shot(t, '3_find', {
      '1': find.text('SDICS App Training – Chiefs – Nandi'),
      '2': find.text('Scan ID card'),
      '3': find.byKey(const Key('id-input')),
      '4': find.byKey(const Key('lookup')),
    });

    await t.tap(find.byKey(const Key('lookup')));
    await waitFor(t, find.text('Kiprotich Arap Sang'));
    await t.enterText(find.byKey(const Key('phone-input')), '0712 345 678');
    await settle(t, 2);
    await t.drag(find.byType(ListView).last, const Offset(0, -330));
    await settle(t, 2);
    await shot(t, '4_phone', {
      '1': find.text('Kiprotich Arap Sang'),
      '2': find.byKey(const Key('phone-input')),
      '3': find.widgetWithText(FilledButton, 'Mark chief present'),
    });

    await t.tap(find.widgetWithText(FilledButton, 'Mark chief present'));
    await settle(t, 6);
    await shot(t, '5_done', {'1': find.byType(SnackBar)});
    await settle(t, 20);

    await t.pageBack();
    await settle(t, 6);
    await t.tap(find.byKey(const Key('tab-People')));
    await waitFor(t, find.text('Wilson Kibet Rotich'));
    await shot(t, '6_present', {
      '1': find.byType(DropdownButtonFormField<String?>),
      '2': find.text('Kiprotich Arap Sang'),
      '3': find.text('0712 345 678 · Kapsabet\nID •••••781'),
    });

    await t.tap(find.byKey(const Key('tab-Insights')));
    await waitFor(t, find.text('CHIEFS PRESENT'));
    await shot(t, '7_insights', {'1': find.text('CHIEFS PRESENT')});
  });
}
