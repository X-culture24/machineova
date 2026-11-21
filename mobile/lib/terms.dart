import 'session.dart';

/// The words the app uses, per organization. Campaigns say voters, mobilize and check in; SDICS
/// chief training says chiefs, onboard (collect their phone number) and mark chief present.
/// Chiefs are looked up in the IEBC voter register like anyone else.
class Terms {
  final bool chiefs;
  const Terms._(this.chiefs);

  static const standard = Terms._(false);
  static const sdicsChiefs = Terms._(true);

  String _p(String campaign, String sdics) => chiefs ? sdics : campaign;

  // Check in (events) → mark a chief present at the training.
  String get checkIn => _p('Check in', 'Mark chief present');
  String get checkInSub => _p('Mark voters present at an event', 'Mark chiefs present at a training');
  String get checkInTile => _p('Mark voters present', 'Find the chief, take their phone number');
  String get checkedIn => _p('Checked in', 'Present');
  String get checkedInDone => _p('checked in', 'marked present');
  String get alreadyCheckedIn => _p('Already checked in today', 'Already marked present today');
  String get phoneLabel => _p('Phone', "Chief's phone number");
  String get checkedInToday => _p('Checked in today', 'Present today');
  String get teamCheckinsToday => _p('Team check-ins today', 'Chiefs present today');
  String get checkins => _p('Check-ins', 'Present');
  String get checkinIntro => _p('Scan or enter an ID to mark a voter present.', 'Scan or enter a chief\'s ID to mark them present.');
  String get event => _p('event', 'training');
  String get eventLabel => _p('Event', 'Training');
  String get chooseEvent => _p('Choose your event', 'Choose your training');

  // Mobilize (drives) → onboard: record the chief and collect their phone number.
  String get mobilize => _p('Mobilize', 'Onboard');
  String get mobilizeSub => _p('Register voters during outreach', "Record a chief and their phone number");
  String get mobilizeTile => _p('Register in the field', 'Collect phone numbers');
  String get mobilizeIntro =>
      _p('Register voters your team reaches in the field.', 'Look up each chief by ID and record their phone number.');
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
  String get topMobilizers => _p('Top mobilizers', 'Top trainers');
  String get peopleMobilized => _p('Voters mobilized', 'Chiefs onboarded');
  String get nobodyMobilized => _p('No one has registered voters yet.', 'No chiefs onboarded yet.');

  // People.
  String get person => _p('voter', 'chief');
  String get personDetails => _p('Voter details', 'Chief details');
  String get nextPerson => _p('Next voter', 'Next chief');
  String get uniquePeople => _p('Unique voters', 'Chiefs present');
  String get notFound => _p('Not found in the register. Fill in their details.',
      'Not found in the IEBC register. Fill in their details.');
  String get notFoundOptional => _p('Not found in the register. Fill in what you can; nothing is required.',
      'Not found in the IEBC register. Fill in what you can; nothing is required. Without an area they are marked out of region.');
  String get fieldRole => _p('Field Agent', 'SDICS Trainer');
  String get startHint => _p('Nothing yet today. Tap + to check in or mobilize.',
      'Nothing yet today. Tap + to mark a chief present.');
  String get fabTooltip => _p('Check in or mobilize', 'Mark chief present');
}

/// The signed-in organization's words.
Terms get terms => session.me?.vocabulary == 'sdics_chiefs' ? Terms.sdicsChiefs : Terms.standard;
