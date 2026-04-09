import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart-side controller for the native Media3 ExoPlayer used for Live TV.
///
/// Commands are sent over [MethodChannel] and state events arrive via
/// [EventChannel]. Each event type is re-broadcast on a dedicated typed
/// stream so the UI layer can subscribe selectively.
///
/// Create one instance per screen. Call [dispose] when the screen is torn
/// down – this cancels the [EventChannel] listener and closes all stream
/// controllers but does **not** release the native player (call [release]
/// explicitly before [dispose] if the player should be freed).
class NativeLivePlayer {
  // ── Platform channels ──────────────────────────────────────────────
  static const _methodChannel = MethodChannel('rawad_iptv/live_player');
  static const _eventChannel = EventChannel('rawad_iptv/live_player/events');

  // ── Event subscription ─────────────────────────────────────────────
  StreamSubscription<dynamic>? _eventSubscription;

  // ── Broadcast stream controllers ───────────────────────────────────
  final _bufferingController = StreamController<bool>.broadcast();
  final _videoSizeController =
      StreamController<({int width, int height})>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _playingController = StreamController<bool>.broadcast();
  final _firstFrameController = StreamController<void>.broadcast();
  final _fpsController = StreamController<double>.broadcast();
  final _positionController = StreamController<int>.broadcast();

  // ── Public streams ─────────────────────────────────────────────────
  /// `true` when the player enters buffering, `false` when ready.
  Stream<bool> get bufferingStream => _bufferingController.stream;

  /// Emits the decoded video resolution whenever it changes.
  Stream<({int width, int height})> get videoSizeStream =>
      _videoSizeController.stream;

  /// Emits a human-readable message on playback errors.
  Stream<String> get errorStream => _errorController.stream;

  /// `true` while the player is actively rendering frames.
  Stream<bool> get playingStream => _playingController.stream;

  /// Fires once when the very first video frame is rendered after a [play].
  Stream<void> get firstFrameStream => _firstFrameController.stream;

  /// Emits the stream frame-rate (FPS) when track info becomes available.
  Stream<double> get fpsStream => _fpsController.stream;

  /// Periodic heartbeat with the current position (ms) – used by the
  /// watchdog timer to detect stalled playback.
  Stream<int> get positionStream => _positionController.stream;

  // ── Constructor ────────────────────────────────────────────────────
  NativeLivePlayer() {
    _eventSubscription = _eventChannel
        .receiveBroadcastStream()
        .listen(_handleEvent, onError: _handleEventError);
  }

  // ── Commands ───────────────────────────────────────────────────────

  /// Create (or re-create) the native ExoPlayer instance.
  Future<void> initialize() async {
    debugPrint('[NativeLivePlayer] initialize');
    await _methodChannel.invokeMethod<void>('initialize');
  }

  /// Start playback of [url] with optional HTTP [headers].
  Future<void> play(String url, {Map<String, String>? headers}) async {
    debugPrint('[NativeLivePlayer] play: $url');
    await _methodChannel.invokeMethod<void>('play', <String, dynamic>{
      'url': url,
      'headers': headers ?? <String, String>{},
    });
  }

  /// Stop playback and clear the current media item (player stays alive).
  Future<void> stop() async {
    debugPrint('[NativeLivePlayer] stop');
    await _methodChannel.invokeMethod<void>('stop');
  }

  /// Release the native ExoPlayer entirely. Call before [dispose].
  Future<void> release() async {
    debugPrint('[NativeLivePlayer] release');
    await _methodChannel.invokeMethod<void>('release');
  }

  /// Tear down the Dart-side streams. Does **not** release the native player.
  void dispose() {
    debugPrint('[NativeLivePlayer] dispose');
    _eventSubscription?.cancel();
    _bufferingController.close();
    _videoSizeController.close();
    _errorController.close();
    _playingController.close();
    _firstFrameController.close();
    _fpsController.close();
    _positionController.close();
  }

  // ── Event routing ──────────────────────────────────────────────────
  void _handleEvent(dynamic raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final name = map['event'] as String? ?? '';

    switch (name) {
      case 'buffering':
        _bufferingController.add(map['value'] as bool);
      case 'videoSize':
        _videoSizeController.add((
          width: map['width'] as int,
          height: map['height'] as int,
        ));
      case 'error':
        _errorController.add(map['message'] as String? ?? 'Unknown error');
      case 'playing':
        _playingController.add(map['value'] as bool);
      case 'firstFrame':
        _firstFrameController.add(null);
      case 'fps':
        _fpsController.add((map['value'] as num).toDouble());
      case 'heartbeat':
        _positionController.add((map['position'] as num).toInt());
      case 'initialized':
        debugPrint('[NativeLivePlayer] native player initialized');
      case 'released':
        debugPrint('[NativeLivePlayer] native player released');
      case 'mediaSet':
        debugPrint('[NativeLivePlayer] media set: ${map['url']}');
      case 'playbackState':
        debugPrint('[NativeLivePlayer] playbackState: ${map['state']}');
      default:
        debugPrint('[NativeLivePlayer] unknown event: $name');
    }
  }

  void _handleEventError(dynamic error) {
    debugPrint('[NativeLivePlayer] EventChannel error: $error');
  }
}
