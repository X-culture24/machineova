import 'package:checkin_mobile/widgets/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ID numbers show only the last 3 digits', () {
    expect(maskId('27553390'), '•••••390');
    expect(maskId('1234567'), '••••567');
    expect(maskId(' 2755 3390 '), '•••••390');
    expect(maskId(null), '—');
    expect(maskId('12'), '•••12');
  });
}
