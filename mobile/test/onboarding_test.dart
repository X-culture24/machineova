import 'package:checkin_mobile/scan/id_parser.dart';
import 'package:checkin_mobile/scan/scan_screen.dart';
import 'package:checkin_mobile/screens/onboarding.dart';
import 'package:checkin_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget app(Widget child) => MaterialApp(theme: buildTheme(), home: child);

  testWidgets('onboarding walks through four pages and remembers it was seen', (t) async {
    var done = false;
    await t.pumpWidget(app(OnboardingScreen(onDone: () => done = true)));
    expect(find.text('Welcome to Checkin'), findsOneWidget);
    expect(await Onboarding.isDone(), isFalse);

    for (final title in ['Scan an ID, find the voter', 'Check in and mobilize', 'Works offline, stays secure']) {
      await t.tap(find.byKey(const Key('onboarding-next')));
      await t.pump(); // start the page animation
      await t.pump(const Duration(milliseconds: 600));
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Get started'), findsOneWidget);
    await t.tap(find.byKey(const Key('onboarding-next')));
    await t.pump();
    expect(done, isTrue);
    expect(await Onboarding.isDone(), isTrue);
  });

  testWidgets('skip finishes onboarding from the first page', (t) async {
    var done = false;
    await t.pumpWidget(app(OnboardingScreen(onDone: () => done = true)));
    await t.tap(find.byKey(const Key('onboarding-skip')));
    await t.pump();
    expect(done, isTrue);
  });

  testWidgets('confirm sheet returns the chosen ID and lets the operator pick another', (t) async {
    String? result;
    await t.pumpWidget(app(Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async => result = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              builder: (_) => const ConfirmIdSheet(candidates: [
                IdCandidate('238469135', IdSource.text, 40, 'Number on the card'),
                IdCandidate('27553390', IdSource.text, 38, 'Number on the card'),
              ]),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    )));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Is this the ID number?'), findsOneWidget); // low confidence → asks
    await t.tap(find.text('27553390'));
    await t.pump();
    expect(find.text('2755 3390'), findsOneWidget);
    await t.tap(find.byKey(const Key('use-scanned-id')));
    await t.pumpAndSettle();
    expect(result, '27553390');
  });
}
