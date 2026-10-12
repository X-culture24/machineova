import 'package:checkin_mobile/scan/id_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('printed text (front of card)', () {
    test('picks the labelled ID number, not the serial number', () {
      const text = 'JAMHURI YA KENYA\nREPUBLIC OF KENYA\nSERIAL NUMBER: 238469135\nID NUMBER: 27553390\n'
          'FULL NAMES\nBRIAN OKOTH\nDATE OF BIRTH\n15.06.1990\nSEX MALE';
      final c = candidatesFromText(text);
      expect(c.first.value, '27553390');
      expect(c.first.score, greaterThanOrEqualTo(IdCandidate.confident));
      expect(c.map((x) => x.value), isNot(contains('238469135')));
    });

    test('tolerates OCR noise inside the number and label', () {
      final c = candidatesFromText('ID NO. 2755 339O');
      expect(c.first.value, '27553390');
    });

    test('ignores dates written as 8 digits', () {
      final c = candidatesFromText('DATE OF BIRTH 19900615\nISSUED 15062012');
      expect(c, isEmpty);
    });

    test('unlabelled number is offered with low confidence', () {
      final c = candidatesFromText('BRIAN OKOTH\n27553390');
      expect(c.single.value, '27553390');
      expect(c.single.score, lessThan(IdCandidate.confident));
    });
  });

  group('MRZ (back of card)', () {
    test('reads the ID from the optional data, not the card number', () {
      const mrz = 'IDKYA2384691357<<27553390<<<<<<\n9006154M3006150KEN<<<<<<<<<<<6\nOKOTH<<BRIAN<<<<<<<<<<<<<<<<<<<';
      final c = candidatesFromText(mrz);
      expect(c.first.value, '27553390');
      expect(c.first.source, IdSource.mrz);
      final card = c.firstWhere((x) => x.value == '238469135', orElse: () => const IdCandidate('', IdSource.mrz, 0, ''));
      expect(card.score, lessThan(IdCandidate.confident));
    });

    test('handles OCR reading < as spaces or K', () {
      const mrz = 'IDKEN238469135 7  27553390KKKKKK\n9006154M3006150KEN           6';
      final c = candidatesFromMrz(mrz);
      expect(c.map((x) => x.value), contains('27553390'));
    });
  });

  group('barcode / QR', () {
    test('bare digits', () {
      expect(candidatesFromBarcode('27553390').single.value, '27553390');
    });
    test('key-value and JSON payloads', () {
      expect(candidatesFromBarcode('NAME=BRIAN OKOTH;IDNO=27553390;SERIAL=238469135').first.value, '27553390');
      expect(candidatesFromBarcode('{"id_number":"27553390","card":"238469135"}').first.value, '27553390');
    });
    test('agreeing sources raise confidence', () {
      final merged = rank([
        const IdCandidate('27553390', IdSource.text, 40, 'x'),
        const IdCandidate('27553390', IdSource.barcode, 45, 'y'),
      ]);
      expect(merged.single.score, 55);
    });
  });

  test('StableReading needs the same best value in consecutive frames', () {
    final s = StableReading(needed: 2);
    final a = [const IdCandidate('27553390', IdSource.label, 95, '')];
    final b = [const IdCandidate('11111111', IdSource.label, 95, '')];
    expect(s.add(a), isNull);
    expect(s.add(b), isNull);
    expect(s.add(b), isNotNull);
    expect(s.add(const []), isNull);
    expect(s.add(a), isNull);
  });
}
