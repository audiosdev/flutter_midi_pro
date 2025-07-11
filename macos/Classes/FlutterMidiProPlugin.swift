
import FlutterMacOS
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var audioEngines: [Int: [AVAudioEngine]] = [:]
  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
  var soundfontURLs: [Int: URL] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger)
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSoundfont":
        let args = call.arguments as! [String: Any]
        let path = args["path"] as! String
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let url = URL(fileURLWithPath: path)
        var chSamplers: [AVAudioUnitSampler] = []
        var chAudioEngines: [AVAudioEngine] = []
        for _ in 0...15 {
            let sampler = AVAudioUnitSampler()
            let audioEngine = AVAudioEngine()
            audioEngine.attach(sampler)
            audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format:nil)
            do {
                try audioEngine.start()
            } catch {
                result(FlutterError(code: "AUDIO_ENGINE_START_FAILED", message: "Failed to start audio engine", details: nil))
                return
            }
            do {
                try sampler.loadSoundBankInstrument(at: url, program: UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank))
            } catch {
                result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
                return
            }
            chSamplers.append(sampler)
            chAudioEngines.append(audioEngine)
        }
        soundfontSamplers[soundfontIndex] = chSamplers
        soundfontURLs[soundfontIndex] = url
        audioEngines[soundfontIndex] = chAudioEngines
        soundfontIndex += 1
        result(soundfontIndex-1)
    case "selectInstrument":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        let soundfontUrl = soundfontURLs[sfId]!
        do {
            try soundfontSampler.loadSoundBankInstrument(at: soundfontUrl, program: UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank))
        } catch {
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
            return
        }
        soundfontSampler.sendProgramChange(UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank), onChannel: UInt8(channel))
        result(nil)
    case "playNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let velocity = args["velocity"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        soundfontSampler.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
        result(nil)
    case "stopNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        soundfontSampler.stopNote(UInt8(note), onChannel: UInt8(channel))
    case "unloadSoundfont":
        let args = call.arguments as! [String:Any]
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        if soundfontSampler == nil {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        audioEngines[sfId]?.forEach { (audioEngine) in
            audioEngine.stop()
        }
        audioEngines.removeValue(forKey: sfId)
        soundfontSamplers.removeValue(forKey: sfId)
        soundfontURLs.removeValue(forKey: sfId)
        result(nil)

case "tuneNotes":
    // 1. More detailed argument parsing with debug logging
    print("[MIDI] TuneNotes called with args: \(String(describing: call.arguments))")
    
    guard let args = call.arguments as? [String: Any] else {
        let error = FlutterError(
            code: "INVALID_ARGS_TYPE",
            message: "Arguments must be a dictionary",
            details: ["received_type": type(of: call.arguments)]
        )
        print("[MIDI] Error: \(error)")
        result(error)
        return
    }
    
    // 2. Validate each parameter separately with detailed errors
    guard let sfId = args["sfId"] as? Int else {
        let error = FlutterError(
            code: "INVALID_SFID",
            message: "sfId must be an Int",
            details: ["received_value": args["sfId"], "expected_type": "Int"]
        )
        print("[MIDI] Error: \(error)")
        result(error)
        return
    }
    
    // Note: key is received but not used - this might be confusing
    guard let _ = args["key"] as? Int else {
        let error = FlutterError(
            code: "INVALID_KEY",
            message: "key must be an Int",
            details: ["received_value": args["key"], "expected_type": "Int"]
        )
        print("[MIDI] Error: \(error)")
        result(error)
        return
    }
    
    guard let tune = args["tune"] as? Double else {
        let error = FlutterError(
            code: "INVALID_TUNE",
            message: "tune must be a Double",
            details: ["received_value": args["tune"], "expected_type": "Double"]
        )
        print("[MIDI] Error: \(error)")
        result(error)
        return
    }
    
    // 3. Thread safety - ensure we're on main thread for sampler access
    DispatchQueue.main.async {
        // 4. Verify sampler dictionary state
        print("[MIDI] Current soundfonts: \(self.soundfontSamplers.keys)")
        
        guard let samplers = self.soundfontSamplers[sfId] else {
            let error = FlutterError(
                code: "SF_NOT_LOADED",
                message: "Soundfont \(sfId) not loaded or already disposed",
                details: ["loaded_sf_ids": Array(self.soundfontSamplers.keys)]
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        let channel = 0 // Default channel
        
        // 5. Validate sampler array
        guard !samplers.isEmpty else {
            let error = FlutterError(
                code: "NO_SAMPLERS",
                message: "No samplers available for soundfont \(sfId)",
                details: nil
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        guard channel >= 0, channel < samplers.count else {
            let error = FlutterError(
                code: "INVALID_CHANNEL",
                message: "Channel \(channel) out of bounds (0..<\(samplers.count))",
                details: nil
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        let sampler = samplers[channel]
        
        // 6. Null check for sampler
        if sampler == nil {
            let error = FlutterError(
                code: "NULL_SAMPLER",
                message: "Sampler is null for sfId \(sfId) channel \(channel)",
                details: nil
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        // 7. Safer pitch bend calculation
        let clampedTune: Double
        if tune.isNaN || tune.isInfinite {
            print("[MIDI] Warning: Received invalid tune value \(tune), using 0")
            clampedTune = 0.0
        } else {
            clampedTune = min(max(tune, -2.0), 2.0)
        }
        
        let bendValue = UInt16((clampedTune / 2.0 + 0.5) * 16383.0)
        let safeBendValue = min(max(bendValue, 0), 16383)
        
        print("[MIDI] Applying pitch bend: sfId=\(sfId), channel=\(channel), tune=\(tune) -> bendValue=\(safeBendValue)")
        
        // 8. Try-catch for MIDI operation
        do {
            try sampler.sendPitchBend(safeBendValue, onChannel: UInt8(channel))
            print("[MIDI] Pitch bend applied successfully")
            result(nil)
        } catch {
            let error = FlutterError(
                code: "MIDI_ERROR",
                message: "Failed to send pitch bend: \(error.localizedDescription)",
                details: ["bend_value": safeBendValue, "channel": channel]
            )
            print("[MIDI] Error: \(error)")
            result(error)
        }
    }
      
    case "dispose":
        audioEngines.forEach { (key, value) in
            value.forEach { (audioEngine) in
                audioEngine.stop()
            }
        }
        audioEngines = [:]
        soundfontSamplers = [:]
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
