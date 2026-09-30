# Vendored `catcher_2` (2.1.12)

This is a local copy of `catcher_2` 2.1.12 (pub.dev), vendored only so this app
can use `cross_file` 0.4.0 before upstream supports it.

Upstream 2.1.12 depends on `cross_file: ^0.3.0`. `cross_file` 0.4.0 is a
breaking federated rewrite that:

- removes `XFile.fromData` / `XFile.saveTo` / `XFile.path` / `XFile.mimeType`
- turns `XFile.name` from a field into `Future<String?> name()`

Only these files were patched; the rest is untouched upstream source:

| File | Change |
| --- | --- |
| `pubspec.yaml` | `cross_file: ^0.4.0`; added `path_provider`; dropped `screenshots` metadata |
| `lib/core/catcher_2_screenshot_manager.dart` | `XFile.fromData(...)+saveTo()` -> `FileSystemXFile` + `writeAsBytes()`; falls back to `getTemporaryDirectory()` when no screenshots path is configured |
| `lib/handlers/discord_handler.dart` | `screenshot.name` -> `await screenshot.name()` |
| `lib/handlers/http_handler.dart` | `report.screenshot!.name` -> `await report.screenshot!.name()` |
| `lib/handlers/slack_handler.dart` | `screenshot.name` -> `await screenshot.name()` |
| `lib/handlers/email_manual_handler.dart` | `report.screenshot?.path` -> `(report.screenshot as FileSystemXFile?)?.path`; added cross_file import |

## When to remove

Delete this folder and the `catcher_2` / `cross_file` entries under
`dependency_overrides` in `pubspec.yaml` as soon as a released `catcher_2`
supports `cross_file >= 0.4.0`.

## Known impact

Screenshots are now materialized as PNG files on disk instead of being kept in
memory, because `cross_file` 0.4 has no in-memory `XFile` on native. This app
does not set `Catcher2Options.screenshotsPath`, so they land in the OS temp
directory. Web screenshots may be unavailable.
