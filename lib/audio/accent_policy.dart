import 'package:ssb_runner/audio/audio_loader.dart';

/// Accent used by incoming stations.
///
/// `auto` keeps the DXCC-based mapping; every other value pins incoming audio
/// to one accent for targeted listening practice.
enum IncomingAccent {
  auto('auto', 'Auto', null),
  us('us', 'US', 'US'),
  uk('uk', 'UK', 'UK'),
  japan('jp', 'Japan', 'JP'),
  russia('ru', 'Russia', 'RU'),
  india('in', 'India / SEA', 'IN');

  const IncomingAccent(this.id, this.label, this.assetDir);

  final String id;
  final String label;

  /// Voice directory this accent reads from; null means "follow the DXCC".
  final String? assetDir;

  static IncomingAccent fromId(String? id) =>
      values.firstWhere((it) => it.id == id, orElse: () => auto);
}

/// Resolves the voice directory for a session. Built when the session starts,
/// so a settings change mid-run cannot alter playback.
class AccentPolicy {
  const AccentPolicy(this.accent);

  final IncomingAccent accent;

  /// The operator's own audio always uses the neutral `Global` voice; only
  /// incoming stations honour the fixed accent.
  String resolve({required bool isMe, required int dxccId}) {
    if (isMe) return myAudioAccentDir;
    return accent.assetDir ?? obtainAccentByDxccId(dxccId);
  }
}
