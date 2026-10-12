/// Pulls a Kenyan national ID number out of what the camera read from a card:
/// printed text (front), the machine-readable zone (MRZ, back), or a barcode / QR payload.
///
/// Cards carry several numbers (serial / card number, dates, the ID number), so this never
/// trusts a bare digit run blindly: it returns ranked [IdCandidate]s and the scan screen asks
/// the operator to confirm before looking anyone up.
library;

enum IdSource { label, mrz, barcode, text }

class IdCandidate {
  final String value;
  final IdSource source;

  /// 0–100. >= [IdCandidate.confident] can be offered as the answer without alternatives.
  final int score;
  final String note;
  const IdCandidate(this.value, this.source, this.score, this.note);

  static const confident = 80;

  @override
  String toString() => '$value ($note, $score)';
}

/// Kenyan ID numbers are 7–9 digits (older IDs are shorter).
final _idDigits = RegExp(r'^\d{7,9}$');

bool isPlausibleId(String s) => _idDigits.hasMatch(s);

/// Candidates from OCR text, best first. [text] is the full recognised text, lines separated by \n.
List<IdCandidate> candidatesFromText(String text) {
  final out = <IdCandidate>[];
  final upper = text.toUpperCase();

  // 1. Labelled: "ID NUMBER 12345678", "ID NO: 1234 5678", "IDNO.12345678".
  final labelled = RegExp(
      r'\bI\.?\s*D\.?\s*(?:NUMBER|NUMB|NUM|NO|N0)\b\.?\s*[:.\-]?\s*([0-9OIl][0-9OIl\s]{5,11}[0-9OIl])');
  for (final m in labelled.allMatches(upper)) {
    final v = _digitsFromOcr(m.group(1)!);
    if (isPlausibleId(v)) out.add(IdCandidate(v, IdSource.label, 95, 'Printed “ID number”'));
  }

  // 2. MRZ (TD1, three lines of 30 on the back of the card).
  out.addAll(candidatesFromMrz(upper));

  // 3. Any other standalone 7–9 digit number that isn't next to "SERIAL"/"CARD NO" or a date.
  final serials = <String>{};
  for (final m in RegExp(
      r'(?:SERIAL(?:\s*(?:NUMBER|NO))?|SER\.|CARD\s*(?:NUMBER|NO)|DOC(?:UMENT)?\s*(?:NUMBER|NO))\.?\s*[:.]?\s*([0-9][0-9 ]{6,11})')
      .allMatches(upper)) {
    serials.add(_digitsFromOcr(m.group(1)!));
  }
  for (final m in RegExp(r'(?<![\d<])(\d{7,9})(?![\d<])').allMatches(upper)) {
    final v = m.group(1)!;
    if (serials.contains(v) || _looksLikeDate(v)) continue;
    out.add(IdCandidate(v, IdSource.text, 40, 'Number on the card'));
  }
  return rank(out);
}

/// Candidates from a TD1 MRZ inside [text]. OCR often reads '<' as 'K', '«' or spaces,
/// so lines are matched loosely and fillers normalised.
List<IdCandidate> candidatesFromMrz(String text) {
  final out = <IdCandidate>[];
  final lines = text
      .split('\n')
      .map((l) => l.replaceAll(RegExp(r'[\s«‹]'), '<').replaceAll(RegExp(r'[^A-Z0-9<]'), ''))
      .toList();
  for (var i = 0; i < lines.length; i++) {
    final l1 = lines[i];
    final start = l1.indexOf(RegExp(r'I[DO<]K(?:YA|EN)'));
    if (start < 0 || l1.length - start < 20) continue;
    final line = l1.substring(start);
    // Document (card) number: positions 5–14. Optional data: 15–29.
    final doc = _digitsFromOcr(line.substring(5, line.length < 14 ? line.length : 14).replaceAll('<', ''));
    final optional = line.length > 15 ? line.substring(15, line.length < 30 ? line.length : 30) : '';
    for (final m in RegExp(r'\d{7,9}').allMatches(optional)) {
      out.add(IdCandidate(m.group(0)!, IdSource.mrz, 85, 'From the MRZ on the back'));
    }
    // Line 2 optional data (positions 18–28) sometimes holds the ID number too.
    if (i + 1 < lines.length && lines[i + 1].length >= 28) {
      final l2 = lines[i + 1];
      for (final m in RegExp(r'\d{7,9}').allMatches(l2.substring(18, l2.length < 29 ? l2.length : 29))) {
        out.add(IdCandidate(m.group(0)!, IdSource.mrz, 75, 'From the MRZ on the back'));
      }
    }
    if (isPlausibleId(doc)) out.add(IdCandidate(doc, IdSource.mrz, 30, 'Card number (MRZ) — usually not the ID'));
  }
  return out;
}

/// Candidates from a barcode / QR payload.
List<IdCandidate> candidatesFromBarcode(String raw) {
  final out = <IdCandidate>[];
  final upper = raw.toUpperCase();
  final trimmed = upper.trim();
  if (isPlausibleId(trimmed)) {
    return [IdCandidate(trimmed, IdSource.barcode, 90, 'Barcode on the card')];
  }
  // Key/value or JSON payloads: "IDNO=12345678", {"id_number":"12345678"}, "NATIONAL ID: 12345678"
  final keyed = RegExp(r'(?:ID[_\s]?(?:NO|NUMBER|NUM)|NATIONAL[_\s]?ID|NID)["\s]*[:=]\s*"?(\d{7,9})\b');
  for (final m in keyed.allMatches(upper)) {
    out.add(IdCandidate(m.group(1)!, IdSource.barcode, 92, 'Barcode on the card'));
  }
  if (out.isEmpty) out.addAll(candidatesFromMrz(upper));
  if (out.isEmpty) {
    for (final m in RegExp(r'(?<!\d)(\d{7,9})(?!\d)').allMatches(upper)) {
      if (!_looksLikeDate(m.group(1)!)) out.add(IdCandidate(m.group(1)!, IdSource.barcode, 45, 'Number in barcode'));
    }
  }
  return rank(out);
}

/// De-duplicates by value (keeping the best score; agreeing sources add confidence) and sorts best first.
List<IdCandidate> rank(List<IdCandidate> all) {
  final byValue = <String, IdCandidate>{};
  final sources = <String, Set<IdSource>>{};
  for (final c in all) {
    sources.putIfAbsent(c.value, () => {}).add(c.source);
    final prev = byValue[c.value];
    if (prev == null || c.score > prev.score) byValue[c.value] = c;
  }
  final ranked = byValue.values.map((c) {
    final agree = sources[c.value]!.length;
    if (agree < 2) return c;
    return IdCandidate(c.value, c.source, (c.score + 10 * (agree - 1)).clamp(0, 100), c.note);
  }).toList()
    ..sort((a, b) => b.score.compareTo(a.score));
  return ranked;
}

/// OCR commonly confuses O→0, I/l→1 inside numbers; drop spaces.
String _digitsFromOcr(String s) =>
    s.replaceAll(RegExp(r'[O]'), '0').replaceAll(RegExp(r'[Il]'), '1').replaceAll(RegExp(r'[^0-9]'), '');

/// 8-digit numbers like 19900615 or 15061990 are dates, not IDs.
bool _looksLikeDate(String v) {
  if (v.length != 8) return false;
  bool ymd(int y, int m, int d) => y >= 1900 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31;
  final a = int.parse(v.substring(0, 4)), b = int.parse(v.substring(4, 6)), c = int.parse(v.substring(6, 8));
  final d1 = int.parse(v.substring(0, 2)), m1 = int.parse(v.substring(2, 4)), y1 = int.parse(v.substring(4, 8));
  return ymd(a, b, c) || ymd(y1, m1, d1);
}

/// Accepts a reading only once the same best value is seen in [needed] consecutive frames.
class StableReading {
  final int needed;
  StableReading({this.needed = 2});
  String? _last;
  int _count = 0;

  /// Returns the candidates once stable, otherwise null.
  List<IdCandidate>? add(List<IdCandidate> frame) {
    if (frame.isEmpty) {
      _last = null;
      _count = 0;
      return null;
    }
    final best = frame.first.value;
    _count = best == _last ? _count + 1 : 1;
    _last = best;
    return _count >= needed ? frame : null;
  }

  void reset() {
    _last = null;
    _count = 0;
  }
}
