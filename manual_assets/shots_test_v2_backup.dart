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
          'id': 12, 'national_id': '99000001', 'full_name': 'Sample Chief Kapropita', 'role': 'CHIEF',
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
    if (path.startsWith('field/roll')) return {'count': people.length, 'next': null, 'results': people};
    if (path.startsWith('field/suggest')) return {'results': people.take(2).toList()};
    if (path.startsWith('citizens/lookup')) {
      return {...people.first, 'registration_status': 'NOT_REGISTERED'};
    }
    return {'success': true};
  }

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    final path = o.path;
    calls.add('${o.method} $path');
    if (o.method == 'POST') sent[path] = o.data;
    if (badLogin && path.startsWith('auth/login')) {
      return ResponseBody.fromString(jsonEncode({'error': {'code': 'INVALID_CREDENTIALS', 'message': 'Invalid credentials'}}), 401,
          headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
    }
    if (down) {
      throw DioException(requestOptions: o, type: DioExceptionType.connectionError);
    }
    return ResponseBody.fromString(jsonEncode(answer(o.method, path)), o.method == 'POST' && path == 'registrations/' ? 201 : 200,
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
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
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
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await settle(tester);
    await tester.ensureVisible(find.text('Officer sign in'));
    await tester.pumpAndSettle();
    await shot(tester, '02_login_error', {'1': find.textContaining('Wrong National ID')});
    server.badLogin = false;
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
    await shot(tester, '06_person', {'1': find.text('KIPROTICH CHEBET KIMUTAI').last, '2': find.text('NOT REGISTERED'), '3': find.text('ID number'), '4': find.text('Mark as registered')});

    await tester.tap(find.text('Mark as registered'));
    await tester.pumpAndSettle();
    await shot(tester, '07_confirm', {'1': find.textContaining('will be recorded'), '2': find.widgetWithText(TextButton, 'Cancel'), '3': find.widgetWithText(FilledButton, 'Register')});

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
    await shot(tester, '12_check_id', {'1': find.byType(TextField).last, '2': find.text('Check'), '3': find.text('Not registered')});

    await tester.tap(find.text('Statistics'));
    await settle(tester);
    await shot(tester, '13_stats', {'1': find.text('Registered today'), '2': find.text('This week'), '3': find.text('Drive to date'), '4': find.text('Still unregistered'), '5': find.text('Drive progress')});

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();
    await shot(tester, '14_account', {'1': find.byIcon(Icons.verified_outlined), '2': find.widgetWithText(OutlinedButton, 'Sign out')});
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    await shot(tester, '15_signout', {'1': find.text('Stay signed in'), '2': find.widgetWithText(TextButton, 'Sign out')});
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
    await tester.tapAt(const Offset(180, 60));
    await tester.pumpAndSettle();
    await finish(tester);
  });
}
