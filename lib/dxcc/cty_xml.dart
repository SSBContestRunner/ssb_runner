import 'package:collection/collection.dart';
import 'package:ssb_runner/dxcc/prefix_row.dart';
import 'package:xml/xml.dart';

/// Parses the `cty.xml` document into prefix rows.
///
/// Used by `tool/generate_prefix_data.dart` to build the bundled TSV; the app
/// itself no longer parses XML at startup.
List<PrefixRow> parseDxccXml(String xmlString) {
  final document = XmlDocument.parse(xmlString);
  final root = document.rootElement;

  final prefixes = document.rootElement.getElement('prefixes');

  if (prefixes == null) {
    return [];
  }

  final notEndPrefix = prefixes.childElements.whereNot(
    (element) => element.childElements.any(
      (childElement) => childElement.name.local == 'end',
    ),
  );

  final entities = root.getElement('entities');

  if (entities == null) {
    return [];
  }

  final deletedEntitieIds = entities.childElements
      .where(
        (element) => element.childElements.any(
          (childElement) =>
              childElement.name.local == 'deleted' &&
              childElement.value == 'true',
        ),
      )
      .map((element) => element.getElement('adif')?.value ?? '')
      .whereNot((id) => id.isEmpty)
      .toSet();

  final validPrefixes = notEndPrefix.whereNot((prefix) {
    final dxccId = prefix.getElement('adif')?.innerText;
    if (dxccId == null) {
      return true;
    }
    return deletedEntitieIds.contains(dxccId);
  });

  return validPrefixes.map((element) {
    return PrefixRow(
      call: element.getElement('call')?.innerText ?? '',
      dxccId: int.tryParse(element.getElement('adif')?.innerText ?? '') ?? 0,
      continent: element.getElement('cont')?.innerText ?? '',
      cqz: int.tryParse(element.getElement('cqz')?.innerText ?? ''),
      ituz: int.tryParse(element.getElement('ituz')?.innerText ?? ''),
    );
  }).toList();
}
