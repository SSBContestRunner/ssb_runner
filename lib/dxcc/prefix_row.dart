/// One entry of the DXCC prefix table, independent of any storage backend.
///
/// The same type is produced by `parseDxccXml` (build time), by the bundled
/// TSV parser and by a database snapshot read, so callers never depend on
/// where the data came from.
class PrefixRow {
  const PrefixRow({
    required this.call,
    required this.dxccId,
    required this.continent,
    this.cqz,
    this.ituz,
  });

  final String call;
  final int dxccId;
  final String continent;
  final int? cqz;
  final int? ituz;

  @override
  String toString() => 'PrefixRow($call, $dxccId, $continent, $cqz, $ituz)';
}
