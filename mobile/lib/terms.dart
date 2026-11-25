import 'session.dart';

/// The words the app uses, per organization. Campaigns say voters, mobilize and check in; SDICS
/// says members, onboard (collect their phone number) and check in member, as its dashboard does.
/// Members are looked up in the IEBC voter register like any other voter.
class Terms {
  final bool chiefs;
  const Terms._(this.chiefs);

  static const standard = Terms._(false);
  static const sdicsChiefs = Terms._(true);

  String _p(String campaign, String sdics) => chiefs ? sdics : campaign;

  // Check in (events).
  String get checkIn => _p('Check in', 'Check in member');
  String get checkInSub => _p('Mark voters present at an event', 'Check members in at an event');
  String get checkInTile => _p('Mark voters present', 'Find the voter, take their phone number');
  String get checkedIn => 'Checked in';
  String get checkedInDone => 'checked in';
  String get alreadyCheckedIn => 'Already checked in today';
  String get phoneLabel => _p('Phone', 'Member’s phone number');
  String get checkedInToday => 'Checked in today';
  String get teamCheckinsToday => _p('Team check-ins today', 'Members checked in today');
  String get checkins => _p('Check-ins', 'Members checked in');
  String get checkinIntro => _p('Scan or enter an ID to mark a voter present.', 'Scan or enter the member’s ID and take their phone number to check them in.');
  String get event => 'event';
  String get eventLabel => 'Event';
  String get chooseEvent => 'Choose your event';

  // Mobilize (drives) → onboard: record the chief and collect their phone number.
  String get mobilize => _p('Mobilize', 'Onboard');
  String get mobilizeSub => _p('Register voters during outreach', 'Record a member and their phone number');
  String get mobilizeTile => _p('Register in the field', 'Collect phone numbers');
  String get mobilizeIntro =>
      _p('Register voters your team reaches in the field.', 'Look up each member by ID and record their phone number.');
  String get mobilized => _p('Mobilized', 'Onboarded');
  String get mobilizedToday => _p('Mobilized today', 'Onboarded today');
  String get teamMobilizedToday => _p('Team mobilized today', 'Team onboarded today');
  String get mobilization => _p('Mobilization', 'Onboarding');
  String get alreadyMobilized => _p('Already mobilized', 'Already onboarded');
  String get drive => _p('drive', 'county');
  String get driveLabel => _p('Drive', 'County');
  String get chooseDrive => _p('Choose your drive', 'Choose your county');
  String get noDrive =>
      _p("You're not assigned to any active drive.", "You're not assigned to any county for onboarding.");
  String get topMobilizers => _p('Top mobilizers', 'Top operators');
  String get peopleMobilized => _p('Voters mobilized', 'Members onboarded');
  String get nobodyMobilized => _p('No one has registered voters yet.', 'No members onboarded yet.');

  // People.
  String get person => _p('voter', 'member');
  String get personDetails => _p('Voter details', 'Member details');
  String get nextPerson => _p('Next voter', 'Next member');
  String get uniquePeople => _p('Unique voters', 'Unique members');
  String get notFound => _p('Not found in the register. Fill in their details.',
      'Not found in the IEBC register. Fill in their details.');
  String get notFoundOptional => _p('Not found in the register. Fill in what you can; nothing is required.',
      'Not found in the IEBC register. Fill in what you can; nothing is required. Without an area they are marked out of region.');
  String get fieldRole => 'Field Agent';
  String get startHint => _p('Nothing yet today. Tap + to check in or mobilize.',
      'Nothing yet today. Tap + to check in a member.');
  String get fabTooltip => _p('Check in or mobilize', 'Check in member');
}

/// The signed-in organization's words.
Terms get terms => session.me?.vocabulary == 'sdics_chiefs' ? Terms.sdicsChiefs : Terms.standard;
