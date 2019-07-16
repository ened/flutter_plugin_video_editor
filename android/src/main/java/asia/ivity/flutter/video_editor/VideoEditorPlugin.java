package asia.ivity.flutter.video_editor;

import android.annotation.SuppressLint;
import android.media.MediaCodec.BufferInfo;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.media.MediaMuxer.OutputFormat;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.EventChannel.EventSink;
import io.flutter.plugin.common.EventChannel.StreamHandler;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * VideoEditorPlugin
 */
public class VideoEditorPlugin implements MethodCallHandler, StreamHandler {

  private static final int DEFAULT_BUFFER_SIZE = 10 * 1024 * 1024;
  private static final String NS = "asia.ivity.flutter";

  private static final String TAG = "VideoEditorPlugin";

  /**
   * Plugin registration.
   */
  public static void registerWith(Registrar registrar) {
    final VideoEditorPlugin plugin = new VideoEditorPlugin();
    final BinaryMessenger messenger = registrar.messenger();

    final MethodChannel channel = new MethodChannel(messenger, NS + "/video_editor");
    channel.setMethodCallHandler(plugin);

    final EventChannel events = new EventChannel(messenger, NS + "/video_editor/progress");
    events.setStreamHandler(plugin);
  }

  @Nullable
  private EventSink progressSink;

  private ExecutorService thumbnailExecutor;
  private Handler mainThreadHandler;

  private boolean cancelled = false;

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull Result result) {
    if (thumbnailExecutor == null) {
      thumbnailExecutor = Executors.newFixedThreadPool(Runtime.getRuntime().availableProcessors());
    }

    if (mainThreadHandler == null) {
      mainThreadHandler = new Handler(Looper.myLooper());
    }

    if (call.method.equals("trimVideo")) {
      final String input = call.argument("input");
      final String output = call.argument("output");
      final Boolean keepAudio = call.argument("keepAudio");
      final Integer startMs = call.argument("startMs");
      final Integer endMs = call.argument("endMs");

      if (input == null || output == null || keepAudio == null || startMs == null
          || endMs == null) {
        result.error(call.method, "invalid params", null);
        return;
      }

      thumbnailExecutor.submit(
          () -> handleTrimVideo(input, output, keepAudio, startMs, endMs)
      );

      result.success(null);
    } else if (call.method.equals("cancelTrim")) {
      cancelled = true;
      result.success(null);
    } else {
      result.notImplemented();
    }
  }

  private void handleTrimVideo(String input, String output, boolean keepAudio, int startMs,
      int endMs) {
    try {

      // Set up MediaExtractor to read from the source.
      MediaExtractor extractor = new MediaExtractor();
      extractor.setDataSource(input);
      final int trackCount = extractor.getTrackCount();
      // Set up MediaMuxer for the destination.
      MediaMuxer muxer = new MediaMuxer(output, OutputFormat.MUXER_OUTPUT_MPEG_4);

      @SuppressLint("UseSparseArrays")
      HashMap<Integer, Integer> indexMap = new HashMap<>();

      for (int i = 0; i < trackCount; i++) {
        extractor.selectTrack(i);
        final MediaFormat format = extractor.getTrackFormat(i);
        final String mime = format.getString(MediaFormat.KEY_MIME);

        Log.d(TAG, "mime: " + mime);

        try {
          if ((keepAudio && mime.startsWith("audio/") && !"audio/unknown".equalsIgnoreCase(mime))
              || (mime.startsWith("video/"))) {
            final int dstIndex = muxer.addTrack(format);
            indexMap.put(i, dstIndex);
          }
        } catch (Throwable e) {
          Log.e(TAG, "Audio Track can not be added. Continuing without Audio.", e);
        }
      }

      boolean sawEOS = false;
//      int bufferSize = DEFAULT_BUFFER_SIZE;
      int frameCount = 0;
      int offset = 100;
      ByteBuffer dstBuf = ByteBuffer.allocate(DEFAULT_BUFFER_SIZE);
      BufferInfo bufferInfo = new BufferInfo();

//            if (degrees >= 0) {
//                muxer.setOrientationHint(degrees)
//            }

      long startUs = startMs * 1000;
      long endUs = endMs * 1000;

      if (startUs > 0) {
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC);
      }

      Log.d(TAG, "About to start muxer");

      muxer.start();

      float lastProgress = 0.0f;

      while (!sawEOS && !cancelled) {
        bufferInfo.offset = offset;
        bufferInfo.size = extractor.readSampleData(dstBuf, offset);

        long sampleTime = extractor.getSampleTime();

        float thisPosition = (sampleTime - startUs) / (float) endUs;
        if (thisPosition != lastProgress) {
          lastProgress = thisPosition;
          updateProgress(input, output, lastProgress, null);
        }

        if (bufferInfo.size < 0 || (sampleTime > endUs)) {
          sawEOS = true;
          bufferInfo.size = 0;
        } else {
          bufferInfo.presentationTimeUs = sampleTime - startUs;
          bufferInfo.flags = extractor.getSampleFlags();

          final int trackIndex = extractor.getSampleTrackIndex();
          Integer track = indexMap.get(trackIndex);

          if (track != null) {
            muxer.writeSampleData(track, dstBuf, bufferInfo);
          }

          extractor.advance();

          frameCount++;
        }
      }

      Log.d(TAG, "Muxer loop completed");

      // Just a regular finish
      if (cancelled) {
        updateProgress(input, output, 0.0f, 5);
        cancelled = false;
      } else {
        updateProgress(input, output, 1.0f, null);
      }

      try {
        muxer.stop();
        muxer.release();
      } catch (Throwable e) {
        Log.w(TAG, "Stopping/Releasing the muxer has failed, ignoring.", e);
      }

    } catch (Throwable e) {
      Log.e(TAG, "muxing failed", e);
      updateProgress(input, output, 0.0f, 4);
    }
  }

  @Override
  public void onListen(Object o, EventSink eventSink) {
    progressSink = eventSink;
  }

  @Override
  public void onCancel(Object o) {
    progressSink = null;
  }

  private void updateProgress(final String input, final String output, final float progress,
      final Integer errorIndex) {
    EventSink sink = this.progressSink;
    if (sink != null) {
      HashMap<String, Object> map = new HashMap<>();

      map.put("input", input);
      map.put("output", output);
      map.put("progress", progress);
      if (errorIndex != null) {
        map.put("errorIndex", errorIndex);
      }

      mainThreadHandler.post(() -> sink.success(map));
    }
  }

}
