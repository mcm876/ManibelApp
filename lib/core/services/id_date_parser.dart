/// Dates pulled out of OCR text from a government ID. Either can be null when
/// the text didn't contain a recognisable one — the backend then routes the
/// submission to manual review instead of guessing.
class IdDates {
  final DateTime? birthDate;
  final DateTime? expiryDate;

  const IdDates({this.birthDate, this.expiryDate});
}

const _months = {
  'JAN': 1,
  'FEB': 2,
  'MAR': 3,
  'APR': 4,
  'MAY': 5,
  'JUN': 6,
  'JUL': 7,
  'AUG': 8,
  'SEP': 9,
  'OCT': 10,
  'NOV': 11,
  'DEC': 12,
};

// Keywords that label each date on Philippine IDs (English + Filipino).
final _birthLabel = RegExp(
  r'BIRTH|BORN|DOB|B-DAY|BIRTHDAY|KAPANGANAKAN|ARAW NG',
);
final _expiryLabel = RegExp(
  r'EXPIR|VALID\s*(UNTIL|THRU|TO)|VALIDITY|PAGKAWALA|EXP\.?\b',
);

// "1990-05-21", "21/05/1990", "05-21-1990", "May 21, 1990", "21 MAY 1990"
final _numericYmd = RegExp(r'\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b');
final _numericDmy = RegExp(r'\b(\d{1,2})[-/.](\d{1,2})[-/.](\d{4})\b');
final _monthFirst = RegExp(
  r'\b([A-Za-z]{3})[A-Za-z]*\.?\s+(\d{1,2}),?\s+(\d{4})\b',
);
final _dayFirst = RegExp(
  r'\b(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\.?,?\s+(\d{4})\b',
);

DateTime? _valid(int y, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31 || y < 1900 || y > 2200) return null;
  final date = DateTime.utc(y, m, d);
  return (date.month == m && date.day == d) ? date : null;
}

/// All dates found in [text], in the order they appear.
List<DateTime> _datesIn(String text) {
  final found = <(int, DateTime)>[];

  for (final m in _numericYmd.allMatches(text)) {
    final d = _valid(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    if (d != null) found.add((m.start, d));
  }
  for (final m in _numericDmy.allMatches(text)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
    // Philippine IDs print MM/DD/YYYY or DD/MM/YYYY; when the first number
    // can't be a month it has to be the day.
    final d = a > 12 ? _valid(y, b, a) : (_valid(y, a, b) ?? _valid(y, b, a));
    if (d != null) found.add((m.start, d));
  }
  for (final m in _monthFirst.allMatches(text)) {
    final mo = _months[m[1]!.toUpperCase()];
    if (mo == null) continue;
    final d = _valid(int.parse(m[3]!), mo, int.parse(m[2]!));
    if (d != null) found.add((m.start, d));
  }
  for (final m in _dayFirst.allMatches(text)) {
    final mo = _months[m[2]!.toUpperCase()];
    if (mo == null) continue;
    final d = _valid(int.parse(m[3]!), mo, int.parse(m[1]!));
    if (d != null) found.add((m.start, d));
  }

  found.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final f in found) f.$2];
}

/// The first date on the same line as, or on the line after, a label match.
DateTime? _dateNearLabel(List<String> lines, RegExp label) {
  for (var i = 0; i < lines.length; i++) {
    if (!label.hasMatch(lines[i].toUpperCase())) continue;
    for (final candidate in [
      lines[i],
      if (i + 1 < lines.length) lines[i + 1],
    ]) {
      final dates = _datesIn(candidate);
      if (dates.isNotEmpty) return dates.first;
    }
  }
  return null;
}

/// Finds the birth and expiry dates in OCR [text] from the front/back of an
/// ID. Only dates next to a label are used; an unlabelled date is never
/// guessed, because a wrong read could wrongly approve or reject someone —
/// unreadable dates go to manual review instead.
IdDates parseIdDates(String text) {
  final lines = text
      .split(RegExp(r'[\r\n]+'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final birth = _dateNearLabel(lines, _birthLabel);
  var expiry = _dateNearLabel(lines, _expiryLabel);

  // Never let one date fill both roles.
  if (birth != null && birth == expiry) expiry = null;

  return IdDates(birthDate: birth, expiryDate: expiry);
}

String toIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
