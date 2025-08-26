import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:ssb_runner/contest_run/log/extract_prefix.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:xml/xml.dart';

class DxccManager {
  final AppDatabase database;

  DxccManager({required this.database});

  late final List<PrefixTableData> _prefixes;

  int findCallsignDxccId(String callsign) {
    final prefix = extractPrefix(callsign);
    final matchPrefixData = _findMatchPrefixData(prefix);

    if (matchPrefixData == null) {
      return -1;
    }

    return matchPrefixData.dxccId;
  }

  String findCallSignContinent(String callsign) {
    final prefix = extractPrefix(callsign);
    final matchPrefixData = _findMatchPrefixData(prefix);

    if (matchPrefixData == null) {
      return '';
    }

    return matchPrefixData.continent;
  }

  PrefixTableData? _findMatchPrefixData(String prefix) {
    String checkedPrefix = prefix;
    PrefixTableData? matchPrefixData;

    while (checkedPrefix.isNotEmpty) {
      matchPrefixData = _prefixes.firstWhereOrNull(
        (element) => element.call == checkedPrefix,
      );

      if (matchPrefixData != null) {
        break;
      }

      checkedPrefix = checkedPrefix.substring(0, checkedPrefix.length - 1);
    }

    return matchPrefixData;
  }

  Future<void> loadDxcc() async {
    final prefixFromDb = await database.select(database.prefixTable).get();

    if (prefixFromDb.isNotEmpty) {
      _prefixes = prefixFromDb;
      return;
    }

    final prefixFromXml = await _loadDxccInternal();
    await _saveToDb(prefixFromXml);
    _prefixes = prefixFromXml;
  }

  Future<List<PrefixTableData>> _loadDxccInternal() async {
    final bytes = Uint8List.sublistView(
      await rootBundle.load('assets/dxcc/cty.xml.gz'),
    );

    return workerManager.execute(() async {
      final archiveBytes = GZipDecoder().decodeBytes(bytes);

      final xmlString = utf8.decode(archiveBytes);

      if (xmlString.isEmpty) {
        throw Exception('Failed to extract DXCC XML');
      }

      return parseDxccXml(xmlString);
    });
  }

  Future<void> _saveToDb(List<PrefixTableData> prefixes) async {
    final insetStatement = database.into(database.prefixTable);

    for (final prefix in prefixes) {
      await insetStatement.insert(
        PrefixTableCompanion.insert(
          call: prefix.call,
          dxccId: prefix.dxccId,
          continent: prefix.continent,
        ),
      );
    }
  }
}

List<PrefixTableData> parseDxccXml(String xmlString) {
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
    return PrefixTableData(
      id: int.tryParse(element.getAttribute('record') ?? '') ?? 0,
      call: element.getElement('call')?.innerText ?? '',
      dxccId: int.tryParse(element.getElement('adif')?.innerText ?? '') ?? 0,
      continent: element.getElement('cont')?.innerText ?? '',
    );
  }).toList();
}
