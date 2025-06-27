import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:ssb_contest_runner/db/app_database.dart';
import 'package:ssb_contest_runner/dxcc/dxcc_prefix.dart';
import 'package:xml/xml.dart';

class DxccManager {
  final AppDatabase database;

  DxccManager({required this.database});

  Future<void> loadDxcc() async {
    final prefix = await (database.select(
      database.prefixTable,
    )..limit(1)).getSingleOrNull();

    if (prefix == null) {
      _loadDxccInternal();
    }
  }

  Future<void> _loadDxccInternal() async {
    final bytes = Uint8List.sublistView(await rootBundle.load('cty.xml.gz'));
    final inputStream = InputMemoryStream.fromList(bytes);
    final archive = ZipDecoder().decodeStream(inputStream);

    final xmlString = _extractDxccXml(archive);

    if (xmlString.isEmpty) {
      throw Exception('Failed to extract DXCC XML');
    }

    final dxccPrefixes = parseDxccXml(xmlString);

    final insetStatement = database.into(database.prefixTable);

    final insertFutures = dxccPrefixes.map((prefix) {
      return insetStatement.insert(
        PrefixTableCompanion.insert(
          call: prefix.call,
          dxccId: prefix.dxccId,
          continent: prefix.continent,
        ),
      );
    });

    await Future.wait(insertFutures);
  }

  String _extractDxccXml(Archive archive) {
    for (final entry in archive) {
      if (entry.isFile && entry.name == 'cty.xml') {
        final xmlBytes = entry.readBytes();

        if (xmlBytes != null) {
          return utf8.decode(xmlBytes);
        }
      }
    }

    return '';
  }
}

List<DxccPrefix> parseDxccXml(String xmlString) {
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
    return DxccPrefix(
      call: element.getElement('call')?.innerText ?? '',
      dxccId: int.tryParse(element.getElement('adif')?.innerText ?? '') ?? 0,
      continent: element.getElement('cont')?.innerText ?? '',
    );
  }).toList();
}
