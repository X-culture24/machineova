/// Kenyan mobile numbers: exactly 10 digits starting 07 or 01. The +254 /
/// 254 forms are accepted and returned as 07…/01…; spaces, dashes, dots and
/// brackets are ignored. null means "not a valid number". The API applies
/// the same rule.
String? kenyanMobile(String input) {
  final s = input.trim();
  if (!RegExp(r'^\+?[0-9 ().-]+$').hasMatch(s)) return null;
  var n = s.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.length == 12 && n.startsWith('254')) n = '0${n.substring(3)}';
  return n.length == 10 && RegExp(r'^0[17]').hasMatch(n) ? n : null;
}

const phoneHint = 'Enter a 10-digit phone number, e.g. 0712 345 678';

/// A form validator: [required] refuses an empty field; any number typed must be valid.
String? Function(String?) phoneValidator({required bool required, String missing = 'Enter the member’s phone number'}) =>
    (s) {
      final v = (s ?? '').trim();
      if (v.isEmpty) return required ? missing : null;
      return kenyanMobile(v) == null ? phoneHint : null;
    };
