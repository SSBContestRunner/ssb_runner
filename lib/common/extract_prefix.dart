final _prefixRegex = RegExp('(([0-9][A-Z])|([A-Z]{1,2}))[0-9]+');

String extractPrefix(String callsign) {
  return _prefixRegex.stringMatch(callsign) ?? '';
}
