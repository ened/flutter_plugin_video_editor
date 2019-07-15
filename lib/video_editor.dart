import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:meta/meta.dart';

enum VideoEditorError {
  inputNotFound,
  outputNotWritable,
  outputNotSupported,
  internalError,
  trimFailed,
  trimCancelled,
}

abstract class VideoTranscodeMode {
  const VideoTranscodeMode();
}

class PassthroughMode extends VideoTranscodeMode {
  const PassthroughMode();
}

class TranscodeMode extends VideoTranscodeMode {
  const TranscodeMode(this.width, this.height);

  final int width;
  final int height;
}

class VideoEditorOptions {
  const VideoEditorOptions(
    this.startMs,
    this.endMs, {
    this.keepAudio = true,
    this.mode: const PassthroughMode(),
  })  : assert(startMs != endMs),
        assert(startMs < endMs);

  final int startMs;
  final int endMs;

  final bool keepAudio;
  final VideoTranscodeMode mode;
}

class VideoTrimProgress {
  const VideoTrimProgress(
    this.input,
    this.output,
    this.progress,
    this.error,
  );

  /// Contains the file to be trimmed.
  final String input;

  /// Contains the output of the trim operation.
  final String output;

  /// Progress of the trim operation. 1.0 = when the operation is completed.
  final double progress;

  /// Optional error when this trim operation has failed.
  final VideoEditorError error;

  @override
  String toString() {
    return 'VideoTrimProgress { input: $input, output: $output, progress: $output, error: $error } ';
  }
}

class VideoEditor {
  static const MethodChannel _channel =
      const MethodChannel('asia.ivity.flutter/video_editor');

  static const EventChannel _progressChannel =
      const EventChannel('asia.ivity.flutter/video_editor/progress');

  Stream<VideoTrimProgress> observeTrimProgress() {
    return _progressChannel
        .receiveBroadcastStream()
        .map<Map<dynamic, dynamic>>((map) => map)
        .map<VideoTrimProgress>((map) => _trimProgressFromMap(map));
  }

  /// The returned future completes normally when the task has been submitted,
  /// or fails with a [VideoEditorError] in case the production can not be started.
  Future<void> trimVideo(
    String input,
    String output,
    VideoEditorOptions options,
  ) async {
    return _channel.invokeMethod('trimVideo', {
      'input': input,
      'output': output,
      'startMs': options.startMs,
      'endMs': options.endMs,
      'keepAudio': options.keepAudio,
      'method': options.mode is PassthroughMode ? 'passthrough' : 'transcode',
      if (options.mode is TranscodeMode) ...{
        'width': (options.mode as TranscodeMode).width,
        'height': (options.mode as TranscodeMode).height,
      }
    });
  }

  Future<void> cancelTrim() {
    return _channel.invokeMethod('cancelTrim');
  }
}

VideoTrimProgress _trimProgressFromMap(Map<dynamic, dynamic> map) {
  return VideoTrimProgress(
    map['input'],
    map['output'],
    map['progress'],
    map['errorIndex'] != null
        ? VideoEditorError.values[map['errorIndex']]
        : null,
  );
}
