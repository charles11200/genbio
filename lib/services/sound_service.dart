import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

/// Short SFX for every game mode: one shared "round start" sound, and a
/// win/lose sound at the end - Survival Mode uses its own lives-based
/// pool-cleared-or-not state for win/lose, Quiz and Matching use
/// isPassingScore (see scoring.dart) since neither has a win/lose state of
/// its own otherwise.
///
/// Every sound is a bundled asset (assets/sounds/*.mp3, see pubspec.yaml),
/// never fetched from a URL - same offline-only rule as the rest of the
/// app. A fresh AudioPlayer per play() call rather than one shared
/// instance: nothing here needs to interrupt a sound already in flight
/// (e.g. leaving a finished round and immediately starting a new one), so
/// each play gets to finish independently instead of cutting the previous
/// one off.
class SoundService {
  // The looping background track, started once for the app's whole
  // lifetime (see main.dart) and never stopped - it plays underneath
  // every screen, not just game rounds. To swap it: drop a new file at
  // assets/sounds/, change this one filename, and update CREDITS.md -
  // nothing else in the app references the filename directly. Sourced
  // from Pixabay, not Mixkit - see CREDITS.md for why.
  static const String _bgmAsset = 'bgm.mp3';

  // Background music sits under the SFX, never over them.
  static const double _bgmVolume = 0.35;
  // Briefly dipped lower still under playWin/playLose specifically, so
  // those two land hard like a real game's win/lose stinger rather than
  // competing with the music - see _playWithDuck.
  static const double _bgmDuckedVolume = 0.08;

  // One shared, long-lived player for BGM (unlike the SFX below, which
  // each get a fresh disposable player) - it needs to keep looping across
  // many play() calls elsewhere, not finish and dispose itself.
  static AudioPlayer? _bgmPlayer;

  static Future<void> playStart() => _play('start.mp3');
  // .wav, not .mp3: the sourced win chime is genuinely WAV-encoded (its
  // Mixkit source served it that way) - renaming the extension to match
  // reality rather than forcing a re-encode for one short SFX.
  static Future<void> playWin() => _playWithDuck('win.wav');
  static Future<void> playLose() => _playWithDuck('lose.mp3');

  /// Starts the looping background track, or does nothing if it's already
  /// playing. Called once, from the app root (see main.dart) - not from
  /// individual screens, so it keeps playing across every screen and
  /// every Navigator push/pop instead of restarting per game round.
  /// Fire-and-forget by design, same as the other play* methods: music is
  /// a nice-to-have, never a reason to block anything from loading.
  static Future<void> startBackgroundMusic() async {
    if (_bgmPlayer != null) return;
    try {
      final player = AudioPlayer();
      _bgmPlayer = player;
      // The bug this fixes: every play*() SFX below creates its own
      // AudioPlayer, which by default asks Android for *exclusive* audio
      // focus. Without this, that request pauses the BGM player outright -
      // and since a fresh SFX player never reliably hands focus back, BGM
      // stayed silent for the rest of the round instead of resuming after
      // a start/win/lose chime finished. mixWithOthers means BGM never
      // requests focus at all, so it can never be told to pause by
      // something else playing - it just keeps looping regardless of
      // whatever SFX plays on top. (Win/lose still audibly stand out - see
      // _playWithDuck - just via a volume dip we control, not by relying
      // on Android's focus system to duck it for us.)
      await player.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers)
            .build(),
      );
      await player.setReleaseMode(ReleaseMode.loop);
      await player.setVolume(_bgmVolume);
      await player.play(AssetSource('sounds/$_bgmAsset'));
    } catch (_) {
      // Same rationale as _play(): missing asset or an unsupported codec
      // should mean "no music", not a broken round.
      _bgmPlayer = null;
    }
  }

  /// Stops and releases the background track. Nothing currently calls
  /// this in normal use - music runs for the app's whole lifetime - but
  /// it's here for a future mute/settings toggle.
  static Future<void> stopBackgroundMusic() async {
    final player = _bgmPlayer;
    _bgmPlayer = null;
    if (player == null) return;
    try {
      await player.stop();
    } catch (_) {
      // Ignore - already stopped/disposed is a fine outcome too.
    } finally {
      await player.dispose();
    }
  }

  static Future<void> _play(String fileName) async {
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/$fileName'));
      // Not awaited - dispose once playback finishes in the background,
      // without blocking whatever UI action triggered the sound.
      unawaited(player.onPlayerComplete.first.then((_) => player.dispose()));
    } catch (_) {
      // A sound effect is a nice-to-have, never a reason to block or crash
      // gameplay - silent mode, an unsupported codec on an unusual device,
      // or a missing asset should all just mean "no sound", not a broken
      // round.
    }
  }

  /// Like _play, but dips the background track's volume for the duration
  /// of this one clip and restores it afterward - used for win/lose so
  /// they land clearly instead of competing with the music, without
  /// depending on Android's audio-focus system to duck it (see the note
  /// in startBackgroundMusic on why that isn't used here).
  static Future<void> _playWithDuck(String fileName) async {
    final bgm = _bgmPlayer;
    if (bgm != null) {
      unawaited(bgm.setVolume(_bgmDuckedVolume).catchError((_) {}));
    }

    void restoreBgmVolume() {
      // Re-read _bgmPlayer rather than closing over `bgm` - the round
      // could end and a new one begin while this clip is still playing.
      unawaited(_bgmPlayer?.setVolume(_bgmVolume).catchError((_) {}));
    }

    try {
      final player = AudioPlayer();
      await player.play(AssetSource('sounds/$fileName'));
      unawaited(player.onPlayerComplete.first.then((_) {
        player.dispose();
        restoreBgmVolume();
      }));
    } catch (_) {
      // The clip itself never started, so there's no completion event to
      // restore the volume on - do it right away instead of leaving BGM
      // ducked for the rest of the round.
      restoreBgmVolume();
    }
  }
}
