import 'dart:convert';
import 'dart:io';

import 'package:checkin_mobile/api/models.dart';
import 'package:checkin_mobile/screens/voter_form.dart';
import 'package:checkin_mobile/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Real (redacted) /api/checkins/lookup responses, parsed and rendered by the app's own code.
void main() {
  final fixtures = jsonDecode(File('test/fixtures_lookup.json').readAsStringSync()) as Map<String, dynamic>;

  for (final name in ['nrb', 'register']) {
    testWidgets('renders $name lookup', (t) async {
      final l = Lookup.fromJson(fixtures[name] as Map<String, dynamic>);
      expect(l.voter, isNotNull);
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: VoterCard(voter: l.voter!, color: AppColors.teal, soft: AppColors.tealSoft, inRegion: l.inRegion),
        ),
      ));
      expect(t.takeException(), isNull);
      expect(find.text(l.voter!.name), findsOneWidget);
    });
  }

  test('unknown ID parses to no voter', () {
    expect(Lookup.fromJson(fixtures['unknown'] as Map<String, dynamic>).voter, isNull);
  });
}
