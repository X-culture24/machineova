import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// How many of the 10 digits are typed so far (+254 counts as the leading 0).
int phoneDigitCount(String input) {
  var n = input.replaceAll(RegExp(r'[^0-9]'), '');
  if (n.startsWith('254') && RegExp(r'^\s*\+?254').hasMatch(input)) n = '0${n.substring(3)}';
  return n.length;
}

/// Keeps phone fields to digits, +, spaces, brackets and dashes.
final phoneInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ().-]')),
  LengthLimitingTextInputFormatter(17),
];

/// The "7 / 10 digits" counter under a phone field, ticked when the number is valid.
InputCounterWidgetBuilder phoneCounter(TextEditingController c) =>
    (context, {required currentLength, required isFocused, maxLength}) {
      final count = phoneDigitCount(c.text);
      final valid = kenyanMobile(c.text) != null;
      final scheme = Theme.of(context).colorScheme;
      final color = valid ? Colors.green.shade700 : count > 10 ? scheme.error : scheme.onSurfaceVariant;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (valid) ...[Icon(Icons.check_circle, size: 14, color: color), const SizedBox(width: 4)],
        Text('$count / 10 digits${count > 10 ? ' — too many' : ''}',
            key: const Key('phone-count'), style: TextStyle(fontSize: 12, color: color)),
      ]);
    };
