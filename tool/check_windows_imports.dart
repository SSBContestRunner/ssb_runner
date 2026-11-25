// Fails when a bundled Windows binary statically imports an API that does not
// exist on the oldest supported Windows version.
//
// Why this exists: `window_manager` 0.7.1 -> nativeapi/cnativeapi imports
// user32!GetDpiForWindow, which only exists from Windows 10 1607 (build
// 14393). Nothing in the build notices that a dependency raised the OS floor;
// it only surfaced when a user on 10240 reported a startup crash (issue #71,
// docs/research/windows-10-rtm-cnativeapi-load-failure.md). Running this over
// the packaged binaries turns that class of regression into a CI failure.
//
// The check is a static import-table read, so it needs no Windows host: the
// Release/ directory produced by `flutter build windows` can be audited from
// any OS. Delay-loaded imports are deliberately ignored -- a delay-load only
// resolves when the code path runs, so it cannot fail `LoadLibrary`.
//
// Usage: dart run tool/check_windows_imports.dart [directory]
// Default directory: build/windows/x64/runner/Release

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// APIs whose first appearance is newer than the declared floor. Anything in
/// this map that a binary imports is an OS-floor regression, unless it is also
/// in [_allowedImports].
///
/// Keep this list sorted by version, and extend it when a new dependency is
/// found to import a newer API; the check can only fail on names it knows.
const Map<String, String> _newerApis = <String, String>{
  // Windows 10 1607 (build 14393).
  'GetDpiForWindow': 'Windows 10 1607',
  'AdjustWindowRectExForDpi': 'Windows 10 1607',
  'EnableNonClientDpiScaling': 'Windows 10 1607',
  'GetSystemMetricsForDpi': 'Windows 10 1607',
  'SystemParametersInfoForDpi': 'Windows 10 1607',
  'GetDpiForSystem': 'Windows 10 1607',
  'SetThreadDpiAwarenessContext': 'Windows 10 1607',
  'GetThreadDpiAwarenessContext': 'Windows 10 1607',
  'GetWindowDpiAwarenessContext': 'Windows 10 1607',
  'GetAwarenessFromDpiAwarenessContext': 'Windows 10 1607',
  'AreDpiAwarenessContextsEqual': 'Windows 10 1607',
  'SetProcessDpiAwarenessContext': 'Windows 10 1607',
  'SetThreadDescription': 'Windows 10 1607',
  'GetThreadDescription': 'Windows 10 1607',
  // Windows 10 1803 (build 17134).
  'VirtualAlloc2': 'Windows 10 1803',
  'VirtualAlloc2FromApp': 'Windows 10 1803',
  'MapViewOfFile3': 'Windows 10 1803',
  'MapViewOfFile3FromApp': 'Windows 10 1803',
  'SetThreadDpiHostingBehavior': 'Windows 10 1803',
  'GetThreadDpiHostingBehavior': 'Windows 10 1803',
  // Windows 10 1809 (build 17763).
  'CreatePseudoConsole': 'Windows 10 1809',
};

/// [_newerApis] entries that a shipped binary is allowed to import anyway.
///
/// cnativeapi imports both DPI calls; they are the only reason Windows 10 1607
/// is the floor. The native pre-check in windows/runner/main.cpp refuses older
/// systems before Dart starts, so a new entry here must come with a matching
/// pre-check (or a fix in the dependency).
const Set<String> _allowedImports = <String>{
  'GetDpiForWindow',
  'AdjustWindowRectExForDpi',
};

const String _defaultDirectory = 'build/windows/x64/runner/Release';

void main(List<String> args) {
  final directory = Directory(args.isEmpty ? _defaultDirectory : args.first);
  if (!directory.existsSync()) {
    stderr.writeln('error: ${directory.path} does not exist.');
    stderr.writeln('Pass the Release directory produced by the Windows build.');
    exit(2);
  }

  final binaries = directory.listSync(recursive: true).whereType<File>().where((
    file,
  ) {
    final path = file.path.toLowerCase();
    return path.endsWith('.dll') || path.endsWith('.exe');
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  if (binaries.isEmpty) {
    stderr.writeln('error: no .dll or .exe files under ${directory.path}.');
    exit(2);
  }

  stdout.writeln(
    'Checking ${binaries.length} binaries for APIs newer than the '
    'Windows 10 1607 floor',
  );

  final failures = <String>[];
  for (final binary in binaries) {
    final name = _relativeName(directory, binary);
    final Set<String> imported;
    try {
      imported = readImportedNames(binary.readAsBytesSync());
    } on FormatException catch (error) {
      failures.add('$name: not a readable PE image (${error.message})');
      continue;
    }

    final offending = imported.where(_isFloorRaising).toList()..sort();
    if (offending.isEmpty) {
      stdout.writeln('  ok      $name');
      continue;
    }
    for (final api in offending) {
      failures.add('$name imports $api (${_newerApis[api]} or newer)');
    }
    final allowed = imported.where(_isAllowed).toList()..sort();
    stdout.writeln(
      '  FAILED  $name'
      '${allowed.isEmpty ? '' : ' (allowed: ${allowed.join(', ')})'}',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'All ${binaries.length} binaries stay within the Windows 10 1607 floor.',
    );
    return;
  }

  stderr.writeln('');
  for (final failure in failures) {
    stderr.writeln('::error::$failure');
  }
  stderr.writeln('');
  stderr.writeln(
    'Raise the documented minimum Windows version (README.md, '
    'windows/packaging/exe/installer.iss, windows/runner/main.cpp) or pin the '
    'dependency that introduced the import.',
  );
  exitCode = 1;
}

bool _isFloorRaising(String api) =>
    _newerApis.containsKey(api) && !_allowedImports.contains(api);

bool _isAllowed(String api) =>
    _newerApis.containsKey(api) && _allowedImports.contains(api);

String _relativeName(Directory root, File file) => file.path
    .substring(root.path.length)
    .replaceFirst(RegExp(r'^[\\/]+'), '')
    .replaceAll('\\', '/');

/// Returns every function name in [bytes]' static import table.
///
/// Only the import directory (data directory entry 1) is read; the export
/// table, relocations and delay-load descriptors are not needed to detect an
/// OS-floor regression.
Set<String> readImportedNames(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);

  int u16(int offset) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('truncated header');
    }
    return data.getUint16(offset, Endian.little);
  }

  int u32(int offset) {
    if (offset < 0 || offset + 4 > bytes.length) {
      throw const FormatException('truncated header');
    }
    return data.getUint32(offset, Endian.little);
  }

  if (u16(0) != 0x5A4D) {
    throw const FormatException('missing MZ signature');
  }
  final peOffset = u32(0x3C);
  if (u32(peOffset) != 0x00004550) {
    throw const FormatException('missing PE signature');
  }

  final sectionCount = u16(peOffset + 6);
  final optionalHeaderSize = u16(peOffset + 20);
  final optionalHeader = peOffset + 24;
  final magic = u16(optionalHeader);
  final is64 = magic == 0x20B;
  if (!is64 && magic != 0x10B) {
    throw FormatException(
      'unknown optional header magic 0x${magic.toRadixString(16)}',
    );
  }

  // The data-directory array sits right after the fixed optional header.
  final dataDirectories = optionalHeader + (is64 ? 112 : 96);
  final importTableRva = u32(dataDirectories + 8);
  final importTableSize = u32(dataDirectories + 12);
  if (importTableRva == 0 || importTableSize == 0) {
    return <String>{};
  }

  final sectionTable = optionalHeader + optionalHeaderSize;
  final sections = <_Section>[];
  for (var index = 0; index < sectionCount; index++) {
    final base = sectionTable + index * 40;
    sections.add(
      _Section(
        virtualSize: u32(base + 8),
        virtualAddress: u32(base + 12),
        rawSize: u32(base + 16),
        rawPointer: u32(base + 20),
      ),
    );
  }

  int toOffset(int rva) {
    for (final section in sections) {
      final span = math.max(section.virtualSize, section.rawSize);
      if (rva < section.virtualAddress ||
          rva >= section.virtualAddress + span) {
        continue;
      }
      final delta = rva - section.virtualAddress;
      if (delta >= section.rawSize) {
        throw FormatException(
          'rva 0x${rva.toRadixString(16)} has no file data',
        );
      }
      return section.rawPointer + delta;
    }
    throw FormatException('rva 0x${rva.toRadixString(16)} is not in a section');
  }

  String readName(int offset) {
    final buffer = StringBuffer();
    for (
      var index = offset;
      index < bytes.length && index < offset + 512;
      index++
    ) {
      final byte = bytes[index];
      if (byte == 0) break;
      buffer.writeCharCode(byte);
    }
    if (buffer.isEmpty) {
      throw const FormatException('empty import name');
    }
    return buffer.toString();
  }

  final names = <String>{};
  // IMAGE_IMPORT_DESCRIPTOR is 20 bytes and the array is zero-terminated.
  var descriptor = toOffset(importTableRva);
  final stride = is64 ? 8 : 4;
  for (var index = 0; index < 4096; index++) {
    final originalFirstThunk = u32(descriptor);
    final nameRva = u32(descriptor + 12);
    final firstThunk = u32(descriptor + 16);
    if (originalFirstThunk == 0 && nameRva == 0 && firstThunk == 0) {
      break;
    }
    descriptor += 20;
    if (nameRva == 0) {
      continue;
    }

    final thunkRva = originalFirstThunk != 0 ? originalFirstThunk : firstThunk;
    if (thunkRva == 0) {
      continue;
    }

    var thunk = toOffset(thunkRva);
    for (var entry = 0; entry < 65536; entry++) {
      final value = is64 ? data.getUint64(thunk, Endian.little) : u32(thunk);
      if (value == 0) {
        break;
      }
      // The high bit marks an ordinal import; those have no name to check.
      // `getUint64` returns a negative int when bit 63 is set.
      final isOrdinal = is64 ? value < 0 : (value & 0x80000000) != 0;
      if (!isOrdinal) {
        // IMAGE_IMPORT_BY_NAME: a 2-byte hint followed by the name.
        names.add(readName(toOffset(value & 0x7FFFFFFF) + 2));
      }
      thunk += stride;
    }
  }
  return names;
}

class _Section {
  const _Section({
    required this.virtualSize,
    required this.virtualAddress,
    required this.rawSize,
    required this.rawPointer,
  });

  final int virtualSize;
  final int virtualAddress;
  final int rawSize;
  final int rawPointer;
}
