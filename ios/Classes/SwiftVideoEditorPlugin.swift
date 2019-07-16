import Flutter

import AVFoundation
import CoreMedia
import UIKit

public enum VideoEditorError: Error {
    case readingFailed
    case exportFailed(Error?)
}

public class SwiftVideoEditorPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "asia.ivity.flutter/video_editor", binaryMessenger: registrar.messenger())
        let instance = SwiftVideoEditorPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        
        let events = FlutterEventChannel(name: "asia.ivity.flutter/video_editor/progress", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance)
        
        registrar.addApplicationDelegate(instance)
    }
    
    private var progressSink: FlutterEventSink? = nil
    private var activeExportSession: AVAssetExportSession? = nil
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "trimVideo" {
            if let dict = call.arguments as? [String : Any] {
                do {
                    let input = dict["input"] as! String
                    let output = dict["output"] as! String
                    let keepAudio = dict["keepAudio"] as! Bool
                    let startMs = dict["startMs"] as! Int
                    let endMs = dict["endMs"] as! Int

                    try handleTrimVideo(input, output, keepAudio: keepAudio, startMs: startMs, endMs: endMs)
                    result(nil)
                } catch {
                    result(FlutterError(code: call.method, message: "internal error", details: nil))
                }
            } else {
                result(FlutterError(code: call.method, message: "invalid params", details: nil))
            }
        } else if call.method == "cancelTrim" {
            self.progressTimer?.invalidate()
            self.activeExportSession?.cancelExport()
            result(nil)
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    private var progressTimer: Timer? = nil
    
    private func handleTrimVideo(_ input: String, _ output: String, keepAudio: Bool, startMs: Int, endMs: Int) throws {
        let sourceAsset = AVAsset(url: URL(fileURLWithPath: input))
        let startS = Float64(startMs) / 1000.0
        let endS = Float64(endMs) / 1000.0
        
        let newStart = CMTime(value: Int64(startS * Float64(sourceAsset.duration.timescale)), timescale: sourceAsset.duration.timescale)
        let newEnd = CMTime(value: Int64(endS * Float64(sourceAsset.duration.timescale)), timescale: sourceAsset.duration.timescale)
        
        let timeRange = CMTimeRangeMake(start: newStart, duration: newEnd - newStart)
        
        let composition = AVMutableComposition()
        let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        if let sourceVideoTrack = sourceAsset.tracks(withMediaType: AVMediaType.video).first {
            try compositionVideoTrack?.insertTimeRange(timeRange, of: sourceVideoTrack, at: CMTime.zero)
        } else {
            throw VideoEditorError.readingFailed
        }
        
        if keepAudio, let sourceAudioTrack = sourceAsset.tracks(withMediaType: AVMediaType.audio).first,
            let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid){
            
            try compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: CMTime.zero)
        }
        
        if let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) {
            self.activeExportSession = session
            // session.timeRange = //
            session.outputURL = URL(fileURLWithPath: output)
            session.outputFileType = AVFileType.mov
            
            self.progressTimer = Timer(timeInterval: 0.01, repeats: true) { timer in
                self.progressSink?([
                    "input": input,
                    "output": output,
                    "progress": NSNumber(value: session.progress)
                    ])
                
                if session.progress > 0.99 {
                    timer.invalidate()
                }
            }
            RunLoop.current.add(self.progressTimer!, forMode: .common)
            
            session.exportAsynchronously {
                switch session.status {
                case .cancelled:
                    self.progressSink?([
                        "input": input,
                        "output": output,
                        "progress": NSNumber(value: 0.0),
                        "errorIndex": 5
                        ])
                    
                case .completed:
                    self.progressSink?([
                        "input": input,
                        "output": output,
                        "progress": NSNumber(value: 1.0)
                        ])
                    
                case .failed:
                    self.progressSink?([
                        "input": input,
                        "output": output,
                        "progress": NSNumber(value: 0.0),
                        "errorIndex": 4
                        ])
                    
                default:
                    print("?? \(session.status.rawValue)")
                    break;
                    
                }

            }
        } else {
            print ("could not construct the session")
            throw VideoEditorError.exportFailed(nil)
        }
        
    }
}

extension SwiftVideoEditorPlugin : FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        progressSink = events
        
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        progressSink = nil
        
        return nil
    }
}

extension SwiftVideoEditorPlugin {
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [AnyHashable : Any] = [:]) -> Bool {
        return true
    }
}
