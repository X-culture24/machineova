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

  testWidgets('out-of-area voter shows where they are registered and where they come from', (t) async {
    final l = Lookup.fromJson({
      'status': 'ready',
      'in_register': true,
      'registered_voter': true,
      'in_region': false,
      'voter': {
        'national_id': '98765433',
        'name': 'Kevin Odhiambo',
        'sex': 'M',
        'dob': '1988-11-21',
        'age': 37,
        'county': 'Kisumu',
        'constituency': 'Kisumu Central',
        'ward': 'Kondele',
        'polling_center': 'Kondele Primary School',
        'registered_on': '2017-01-20',
        'source': 'voter_register',
        'home': {'county': 'Siaya', 'sub_county': 'Bondo', 'location': 'Sakwa Central', 'village': 'Sirongo'},
      },
    });
    expect(l.inRegion, isFalse);
    expect(l.voter!.home!.line, 'Sirongo, Sakwa Central, Bondo, Siaya');
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: Scaffold(body: OriginPanel(l.voter!))));
    expect(t.takeException(), isNull);
    expect(find.text('Outside this area'), findsOneWidget);
    expect(find.text('Kondele, Kisumu Central, Kisumu · Kondele Primary School'), findsOneWidget);
    expect(find.text('Sirongo, Sakwa Central, Bondo, Siaya'), findsOneWidget);
  });

  test('unknown ID parses to no voter', () {
    expect(Lookup.fromJson(fixtures['unknown'] as Map<String, dynamic>).voter, isNull);
  });
}
