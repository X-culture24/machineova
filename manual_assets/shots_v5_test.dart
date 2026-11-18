// Opens every page of the app as a chief would, against a fake SDICS, on a
// small phone screen. Any crash, missing provider or layout overflow fails
// the test. Run before every release: flutter test test/walkthrough_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:sdics_field/core/api.dart';
import 'package:sdics_field/core/sdics.dart';
import 'package:sdics_field/main.dart';

/// A stand-in SDICS: canned answers, and a log of what the app sent.
class FakeSdics implements HttpClientAdapter {
  final calls = <String>[];
  final sent = <String, Object?>{};
  bool down = false;
  bool badLogin = false;
  bool regOpen = true; // true: every request fails like no signal
  bool pinEnded = false; // sign-in answers PIN_INVALIDATED
  bool subChief = false; // field/me/ answers as a sub-chief
  bool clerk = false; // an IEBC clerk
  final queries = <String, Map<String, dynamic>>{};

  static final kisumu = [
    for (final p in [
      ['41', 'AWINO ACHIENG ODHIAMBO', 'ODHIAMBO OKOTH', 'KAKAN'],
      ['42', 'OTIENO OMONDI SAMPLE', 'OMONDI OGOLA', 'KONYANGO'],
      ['43', 'ATIENO ADHIAMBO DEMO', 'OCHIENG OWINO', 'KAKAN'],
    ])
      {
        'id': int.parse(p[0]), 'national_id': '4123456${p[0].substring(1)}', 'full_name': p[1], 'father_name': p[2],
        'clan': p[3], 'family': 'ODHIAMBO', 'phone_number': '0700000000', 'county': 'KISUMU', 'district': 'KISUMU EAST',
        'division': 'WINAM', 'location': 'KOLWA EAST', 'sub_location': 'BUOYE', 'village': 'NYALUNYA',
      },
  ];

  static final people = [
    for (var i = 1; i <= 3; i++)
      {
        'id': i, 'national_id': '3000000$i', 'full_name': ['', 'KIPROTICH CHEBET KIMUTAI', 'CHEBET JEPKOSGEI SAMPLE', 'ACHIENG AKINYI DEMO'][i],
        'father_name': 'KIMUTAI ARAP SANG', 'clan': 'TALAI', 'family': 'KIMUTAI', 'phone_number': '0700000000',
        'county': 'BARINGO', 'district': 'BARINGO CENTRAL', 'division': 'KABARNET', 'location': 'KAPROPITA',
        'sub_location': 'KAPROPITA', 'village': 'KAPLELACH',
      },
  ];

  Object? answer(String method, String path) {
    if (path.startsWith('auth/login')) {
      return {
        'access_token': 'a', 'refresh_token': 'r',
        'officer': {
          'id': 12, 'national_id': '99000001', 'full_name': clerk ? 'Sample Clerk Wanjiru' : 'Sample Chief Kapropita', 'role': 'CHIEF',
          'daily_target': 40, 'allow_daily_total_submissions': true,
          'assigned_locations': [
            {'county': 'BARINGO', 'district': 'BARINGO CENTRAL', 'division': 'KABARNET', 'location': 'KAPROPITA', 'registration_enabled': regOpen},
          ],
        },
      };
    }
    if (path.startsWith('dashboard/summary')) {
      return {
        'officer_daily_target': 40, 'officer_registrations_today': 4, 'officer_registrations_this_week': 30,
        'officer_scope_unregistered': 1234, 'officer_scope_registered': 5000, 'officer_scope_total': 6234,
        'officer_scope_converted': 20, 'officer_scope_pool': 1254, 'officer_scope_conversion_percentage': 1.6,
      };
    }
    if (path.startsWith('field/my-day')) {
      return {'app_today': 5, 'paper_today': 12, 'total_today': 17, 'app_week': 30, 'paper_week': 12, 'total_week': 42, 'daily_target': 40};
    }
    if (path.startsWith('field/me')) {
      return {
        'id': 12, 'role': 'CHIEF', 'title': clerk ? 'CLERK' : (subChief ? 'SUBCHIEF' : ''), 'unregistered_total': people.length,
        'areas': [
          {'county': 'BARINGO', 'district': 'BARINGO CENTRAL', 'division': 'KABARNET', 'location': 'KAPROPITA',
            if (subChief) 'sub_location': 'KAPKUT EAST'},
        ],
      };
    }
    if (path.startsWith('field/lookup')) {
      if (queries[path]?['id'] == '41234561') {
        return {
          ...kisumu.first, 'registration_status': 'NOT_REGISTERED', 'can_register': clerk,
          if (!clerk)
            'reason': 'Not in your area. This person lives in KOLWA EAST location, BUOYE sublocation '
                '(KISUMU EAST, KISUMU). You can only register people in your location: KAPROPITA (BARINGO CENTRAL). '
                'The chief of KOLWA EAST or an IEBC clerk can register them.',
        };
      }
      return {...people.first, 'registration_status': 'NOT_REGISTERED', 'can_register': true};
    }
    final roll = people;
    if (path.startsWith('field/roll')) return {'count': roll.length, 'next': null, 'results': roll};
    if (path.startsWith('field/suggest')) return {'results': roll.take(2).toList()};
    return {'success': true};
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final path = o.path;
    calls.add('${o.method} $path');
    queries[path] = Map<String, dynamic>.from(o.queryParameters);
    if (o.method == 'POST') sent[path] = o.data;
    if (pinEnded && path.startsWith('auth/login')) {
      return ResponseBody.fromString(jsonEncode({'error': {'code': 'PIN_INVALIDATED', 'message': 'PIN invalidated'}}), 401,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (badLogin && path.startsWith('auth/login')) {
      return ResponseBody.fromString(jsonEncode({'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Invalid credentials'}}), 401,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (down) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(jsonEncode(answer(o.method, path)), o.method == 'POST' && path == 'field/register/' ? 201 : 200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        });
  }

  @override
  void close({bool force = false}) {}
}

class FakePaths extends Fake with MockPlatformInterfaceMixin implements PathProviderPlatform {
  FakePaths(this.dir);
  final String dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
}


Future<void> loadFont(String family, List<String> files) async {
  final l = FontLoader(family);
  for (final f in files) {
    final b = File(f).readAsBytesSync();
    l.addFont(Future.value(ByteData.view(Uint8List.fromList(b).buffer)));
  }
  await l.load();
}

void main() {
  late FakeSdics server;
  late Sdics sdics;
  late Directory tmp;

  setUpAll(() async {
    await loadFont('Lexend', [for (final w in [400, 500, 600, 700, 800]) 'assets/fonts/Lexend-$w.ttf']);
    await loadFont('MaterialIcons', ['/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    await loadFont('Roboto', ['/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf']);
    // labels with no font family (the button themes) fall back to the test
    // font; on a phone they are Roboto, so draw them in Roboto here too
    await loadFont('FlutterTest', ['/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf']);
    await loadFont('Ahem', ['/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Medium.ttf', '/Users/lawrence/development/flutter/bin/cache/artifacts/material_fonts/Roboto-Bold.ttf']);
  });

  setUp(() async {
    await initializeDateFormatting('en_KE');
    FlutterSecureStorage.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('sdics-shots');
    PathProviderPlatform.instance = FakePaths(tmp.path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('net.nfet.printing'), (_) async => 1);
    server = FakeSdics();
    sdics = Sdics(client: Api(adapter: server));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 300));
    }
  }


  Future<void> waitFor(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 60 && !tester.any(f); i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  final rects = <String, Map<String, List<double>>>{};
  Future<void> shot(WidgetTester tester, String name, [Map<String, Finder> marks = const {}]) async {
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/$name.png'));
    final m = <String, List<double>>{};
    marks.forEach((k, f) {
      if (tester.any(f)) {
        final r = tester.getRect(f.first);
        m[k] = [r.left * 2, r.top * 2, r.right * 2, r.bottom * 2];
      } else {
        m[k] = [];
      }
    });
    rects[name] = m;
    File('test/shots/rects.json').writeAsStringSync(const JsonEncoder.withIndent(' ').convert(rects));
  }

  Future<void> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(720, 1560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(value: sdics, child: const SdicsApp()));
    await tester.runAsync(sdics.restore);
    await tester.pumpAndSettle();
  }

  Future<void> signIn(WidgetTester tester) async {
    await tester.enterText(find.byType(TextFormField).at(0), '99000001');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    server.down = false;
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
  }

  testWidgets('main flow', (tester) async {
    await boot(tester);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, '01_login', {'1': find.byType(TextFormField).at(0), '2': find.byType(TextFormField).at(1), '3': find.byTooltip('Show PIN'), '4': find.byType(FilledButton), '5': find.textContaining('Forgot your PIN')});
    server.badLogin = true;
    await tester.enterText(find.byType(TextFormField).at(0), '99000001');
    await tester.enterText(find.byType(TextFormField).at(1), '1111');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('login-title')));
    await tester.pumpAndSettle();
    await shot(tester, '02_login_error', {'1': find.textContaining('Wrong National ID')});
    server.badLogin = false;
    server.pinEnded = true;
    await tester.enterText(find.byType(TextFormField).at(1), '2222');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('login-title')));
    await tester.pumpAndSettle();
    await shot(tester, '02b_pin_ended', {'1': find.textContaining('no longer valid')});
    server.pinEnded = false;
    await signIn(tester);
    await shot(tester, '03_home', {'1': find.byTooltip('Account'), '2': find.textContaining('to go'), '3': find.text('Open the roll'), '4': find.text('Check an ID'), '5': find.text('Daily total'), '6': find.text('Correct figure'), '7': find.byType(NavigationBar)});

    await tester.tap(find.text('Roll'));
    await settle(tester);
    await shot(tester, '04_roll', {'1': find.text('Still to register'), '2': find.textContaining('Saved for offline'), '3': find.byType(TextField).first, '4': find.text('KIPROTICH CHEBET KIMUTAI'), '5': find.byTooltip('Download roll (PDF)')});

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'chebet');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await shot(tester, '05_search', {'1': find.byType(TextField).first, '2': find.text('KIPROTICH CHEBET KIMUTAI'), '3': find.textContaining('Show all matches')});
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);

    await tester.tap(find.text('KIPROTICH CHEBET KIMUTAI').first);
    await settle(tester);
    await shot(tester, '06_person', {'1': find.text('KIPROTICH CHEBET KIMUTAI').last, '2': find.text('NOT REGISTERED'), '3': find.text('ID number'), '4': find.text('Mark as registered'), '5': find.byKey(const Key('sheet-back'))});

    await tester.tap(find.text('Mark as registered'));
    await tester.pumpAndSettle();
    await shot(tester, '07_confirm', {'1': find.textContaining('will be recorded'), '2': find.byKey(const Key('back-button')), '3': find.widgetWithText(FilledButton, 'Register')});

    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await waitFor(tester, find.textContaining('is now registered'));
    await shot(tester, '08_success', {'1': find.textContaining('is now registered'), '2': find.textContaining('today')});
    await settle(tester);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    // Offline
    server.down = true;
    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    await tester.tap(find.text('CHEBET JEPKOSGEI SAMPLE').first);
    await settle(tester);
    await tester.tap(find.text('Mark as registered'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await waitFor(tester, find.textContaining('saved as registered'));
    await shot(tester, '09_offline_saved', {'1': find.textContaining('waiting to send'), '2': find.textContaining('saved as registered')});
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '10_offline_banner', {'1': find.textContaining('waiting to send'), '2': find.text('Sync now')});
    await tester.tap(find.byIcon(Icons.cloud_off_rounded).first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await shot(tester, '11_offline_sheet', {'1': find.text('Offline mode'), '2': find.text('1 waiting to send')});
    await tester.tapAt(const Offset(180, 60));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Check ID (online again)
    server.down = false;
    await tester.tap(find.text('Check ID'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '30000001');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await shot(tester, '12_check_id', {'1': find.byType(TextField).last, '2': find.text('Check'), '3': find.text('Not registered'), '4': find.text('Open and register')});
    await tester.enterText(find.byType(TextField).last, '41234561');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await shot(tester, '12b_check_id_elsewhere', {'1': find.text('AWINO ACHIENG ODHIAMBO'), '2': find.textContaining('KOLWA EAST').first, '3': find.textContaining('Not in your area')});

    await tester.tap(find.text('Statistics'));
    await settle(tester);
    await shot(tester, '13_stats', {'1': find.text('Registered today'), '2': find.text('This week'), '3': find.text('Drive to date'), '4': find.text('Still unregistered'), '5': find.text('Drive progress')});

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await shot(tester, '14_account', {'1': find.byIcon(Icons.verified_outlined), '2': find.widgetWithText(OutlinedButton, 'Sign out')});
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await shot(tester, '15_signout', {'1': find.text('Stay signed in'), '2': find.widgetWithText(TextButton, 'Sign out'), '3': find.textContaining('Your PIN stays')});
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('registration not open', (tester) async {
    server.regOpen = false;
    await boot(tester);
    await signIn(tester);
    await shot(tester, '16_not_open_home', {'1': find.textContaining("isn't open")});
    await tester.tap(find.text('Roll'));
    await settle(tester);
    await tester.tap(find.text('KIPROTICH CHEBET KIMUTAI').first);
    await settle(tester);
    await shot(tester, '17_not_open_person', {'1': find.textContaining("isn't open in this county")});
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('sub-chief', (tester) async {
    server.subChief = true;
    await boot(tester);
    await signIn(tester);
    await settle(tester);
    await shot(tester, '18_subchief_home', {'1': find.text('Sub-chief'), '2': find.textContaining('KAPKUT EAST')});
    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await shot(tester, '19_subchief_account', {'1': find.textContaining('Sub-chief ·'), '2': find.textContaining('KAPKUT EAST').last});
    server.subChief = false;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await settle(tester);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('daily total', (tester) async {
    await boot(tester);
    await signIn(tester);
    await tester.ensureVisible(find.text('Daily total').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Daily total').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '12');
    await tester.enterText(find.byType(TextField).at(1), 'No network in the village');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot(tester, '20_daily_total', {'1': find.byType(TextField).at(0), '2': find.byType(TextField).at(1), '3': find.text('Send daily total'), '4': find.byTooltip('Back')});
    await tester.tap(find.byTooltip('Back').last);
    await settle(tester);
    await finish(tester);
  });

  testWidgets('clerk', (tester) async {
    server.clerk = true;
    await boot(tester);
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.enterText(find.byType(TextFormField).at(0), '99000001');
    await tester.enterText(find.byType(TextFormField).at(1), '1234');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await shot(tester, 'c01_login', {'1': find.byType(TextFormField).at(0), '2': find.byType(TextFormField).at(1), '3': find.byType(FilledButton), '4': find.textContaining('1-page guide')});
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester);
    await settle(tester);
    await shot(tester, 'c02_home', {'1': find.text('Clerk'), '2': find.textContaining('KAPROPITA').first, '3': find.textContaining('to go'), '4': find.byType(NavigationBar)});

    await tester.tap(find.text('Roll'));
    await settle(tester);
    await shot(tester, 'c06_roll', {'1': find.text('Still to register'), '2': find.byType(TextField).first, '3': find.text('KIPROTICH CHEBET KIMUTAI')});

    await tester.tap(find.byType(TextField).first);
    await tester.enterText(find.byType(TextField).first, 'chebet');
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    await shot(tester, 'c07_search', {'1': find.byType(TextField).first, '2': find.text('KIPROTICH CHEBET KIMUTAI')});
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await settle(tester);
    await tester.tap(find.text('KIPROTICH CHEBET KIMUTAI').first);
    await settle(tester);
    await shot(tester, 'c08_person', {'1': find.text('KIPROTICH CHEBET KIMUTAI').last, '2': find.text('NOT REGISTERED'), '3': find.text('Mark as registered')});
    await tester.tap(find.text('Mark as registered'));
    await tester.pumpAndSettle();
    await shot(tester, 'c09_confirm', {'1': find.textContaining('will be recorded'), '2': find.widgetWithText(FilledButton, 'Register')});
    await tester.tap(find.widgetWithText(FilledButton, 'Register'));
    await waitFor(tester, find.textContaining('is now registered'));
    await shot(tester, 'c10_success', {'1': find.textContaining('is now registered')});
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Check ID'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '41234561');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    await shot(tester, 'c11_check_id', {'1': find.byType(TextField).last, '2': find.text('Not registered'), '3': find.text('Open and register')});
    await tester.tap(find.text('Open and register'));
    await settle(tester);
    await shot(tester, 'c12_person_elsewhere', {'1': find.text('AWINO ACHIENG ODHIAMBO').last, '2': find.textContaining('KOLWA EAST').last, '3': find.text('Mark as registered')});
    await tester.tap(find.byKey(const Key('sheet-back')));
    await tester.pumpAndSettle();
    await finish(tester);
  });
}
