import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:ssb_runner/common/extract_prefix.dart';
import 'package:ssb_runner/db/app_database.dart';
import 'package:ssb_runner/logging/app_logger.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:xml/xml.dart';

class DxccManager {
  final AppDatabase database;

  DxccManager({required this.database});

  /// Cached prefixes, empty until [loadDxcc] succeeds.
  List<PrefixTableData> _prefixes = const <PrefixTableData>[];

  Map<String, int> _prefixToDxccMap = const <String, int>{};

  int findCallsignDxccId(String callsign) {
    final prefix = extractPrefix(callsign);

    String checkedPrefix = prefix;
    int? matchPrefixDxccId;

    while (checkedPrefix.isNotEmpty) {
      matchPrefixDxccId = _prefixToDxccMap[checkedPrefix];

      if (matchPrefixDxccId != null) {
        break;
      }

      checkedPrefix = checkedPrefix.substring(0, checkedPrefix.length - 1);
    }

    if (matchPrefixDxccId == null) {
      return -1;
    }

    return matchPrefixDxccId;
  }

  /// CQ zone for a callsign, or null when the cty data has no match.
  int? findCallsignCqZone(String callsign) =>
      _findMatchPrefixData(extractPrefix(callsign))?.cqz;

  /// ITU zone for a callsign, or null (the bundled cty asset has no ituz).
  int? findCallsignItuZone(String callsign) =>
      _findMatchPrefixData(extractPrefix(callsign))?.ituz;

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
    final cachedPrefixes = await _readCachedPrefixes();

    if (cachedPrefixes != null && cachedPrefixes.isNotEmpty) {
      _assignPrefixes(cachedPrefixes);
      return;
    }

    final prefixFromXml = await _loadDxccInternal();
    _assignPrefixes(prefixFromXml);
    await _saveToDb(prefixFromXml);
  }

  /// Reads the cached prefix table, or `null` when the database cannot be read.
  ///
  /// The cache is an optimisation: an unusable database must still let the app
  /// resolve callsigns from the bundled asset.
  Future<List<PrefixTableData>?> _readCachedPrefixes() async {
    try {
      return await database.select(database.prefixTable).get();
    } catch (error, stackTrace) {
      log.warn(
        'dxcc cache read failed, loading from asset',
        tag: 'dxcc',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  void _assignPrefixes(List<PrefixTableData> prefixes) {
    _prefixes = prefixes;
    _prefixToDxccMap = {
      for (var element in _prefixes) element.call: element.dxccId,
    };
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

  /// Stores the prefix cache; a failure only costs the next launch some parsing.
  Future<void> _saveToDb(List<PrefixTableData> prefixes) async {
    try {
      await database.transaction(() async {
        final insertStatement = database.into(database.prefixTable);

        for (final prefix in prefixes) {
          await insertStatement.insert(
            PrefixTableCompanion.insert(
              call: prefix.call,
              dxccId: prefix.dxccId,
              continent: prefix.continent,
              cqz: Value(prefix.cqz),
              ituz: Value(prefix.ituz),
            ),
          );
        }
      });
    } catch (error, stackTrace) {
      log.warn(
        'dxcc cache write failed, continuing without cache',
        tag: 'dxcc',
        error: error,
        stackTrace: stackTrace,
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
      cqz: int.tryParse(element.getElement('cqz')?.innerText ?? ''),
      ituz: int.tryParse(element.getElement('ituz')?.innerText ?? ''),
    );
  }).toList();
}
