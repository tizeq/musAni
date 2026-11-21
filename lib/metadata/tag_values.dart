/// Tag values are lists, never punctuation-delimited strings. In particular,
/// commas, slashes, ampersands and semicolons can be part of an artist's name.
List<String> artistValues(Iterable<String> values) {
  final seen = <String>{};
  return [
    for (final value in values.map((value) => value.trim()))
      if (value.isNotEmpty && seen.add(value.toLowerCase())) value,
  ];
}

List<String> trackArtistValues(
  Map<String, List<String>> properties, {
  String fallback = '',
}) {
  // Picard's ARTISTS is an explicit list, while ARTIST may be a single credit
  // such as "A feat. B". Never try to reconstruct that list from punctuation.
  final explicit = artistValues(properties['ARTISTS'] ?? const []);
  return explicit.isNotEmpty
      ? explicit
      : artistValues(properties['ARTIST'] ?? [fallback]);
}

String albumArtistValue(Map<String, List<String>> properties) =>
    artistValues(properties['ALBUMARTIST'] ?? const []).join(' / ');
