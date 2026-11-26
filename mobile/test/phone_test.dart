import 'package:flutter_test/flutter_test.dart';
import 'package:checkin_mobile/phone.dart';

void main() {
  test('Kenyan mobile numbers: 10 digits, 07 or 01, +254 accepted', () {
    for (final (input, want) in const [
      ('0712345678', '0712345678'),
      ('0712 345 678', '0712345678'),
      ('0112-345-678', '0112345678'),
      ('+254712345678', '0712345678'),
      ('254 712 345 678', '0712345678'),
    ]) {
      expect(kenyanMobile(input), want, reason: input);
    }
    for (final bad in const ['', '712345678', '07123456789', '071234567', '0212345678', '+255712345678', '07123x5678']) {
      expect(kenyanMobile(bad), isNull, reason: bad);
    }
  });

  test('validator: required vs optional', () {
    final required = phoneValidator(required: true), optional = phoneValidator(required: false);
    expect(required(''), isNotNull);
    expect(optional(''), isNull);
    expect(optional('0712'), phoneHint);
    expect(required('0712 345 678'), isNull);
  });
}
