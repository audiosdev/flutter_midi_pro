
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
    // Debug logging
    print("[MIDI] tuneNotes called with arguments: \(String(describing: call.arguments))")
    
    // Argument validation
    guard let args = call.arguments as? [String: Any] else {
        let error = FlutterError(
            code: "INVALID_ARGUMENTS",
            message: "Arguments must be a dictionary",
            details: ["type": type(of: call.arguments)]
        )
        print("[MIDI] Validation error: \(error)")
        result(error)
        return
    }
    
    guard let sfId = args["sfId"] as? Int else {
        let error = FlutterError(
            code: "INVALID_SFID",
            message: "sfId must be an Int",
            details: ["received": args["sfId"]]
        )
        print("[MIDI] Validation error: \(error)")
        result(error)
        return
    }
    
    // Note: key is received but not used in current implementation
    _ = args["key"] as? Int  // Silencing unused warning
    
    guard let tune = args["tune"] as? Double else {
        let error = FlutterError(
            code: "INVALID_TUNE",
            message: "tune must be a Double",
            details: ["received": args["tune"]]
        )
        print("[MIDI] Validation error: \(error)")
        result(error)
        return
    }
    
    // Ensure operation happens on main thread
    DispatchQueue.main.async {
        // Debug current state
        print("[MIDI] Current soundfonts: \(self.soundfontSamplers.keys.map { String($0) }.joined(separator: ", "))")
        
        // Validate soundfont exists
        guard let samplers = self.soundfontSamplers[sfId] else {
            let error = FlutterError(
                code: "SOUNDFONT_NOT_FOUND",
                message: "Soundfont with ID \(sfId) not loaded",
                details: ["available_soundfonts": Array(self.soundfontSamplers.keys)]
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        let channel = 0  // Default channel
        
        // Validate channel bounds
        guard channel >= 0, channel < samplers.count else {
            let error = FlutterError(
                code: "INVALID_CHANNEL",
                message: "Channel \(channel) is out of bounds (0..<\(samplers.count))",
                details: nil
            )
            print("[MIDI] Error: \(error)")
            result(error)
            return
        }
        
        let sampler = samplers[channel]
        
        // Calculate pitch bend value
        let clampedTune: Double
        if tune.isNaN || tune.isInfinite {
            print("[MIDI] Warning: Invalid tune value \(tune), defaulting to 0")
            clampedTune = 0.0
        } else {
            clampedTune = min(max(tune, -2.0), 2.0)
        }
        
        let bendValue = UInt16((clampedTune / 2.0 + 0.5) * 16383.0)
        let safeBendValue = min(max(bendValue, 0), 16383)
        
        print("[MIDI] Applying pitch bend - SF: \(sfId), Channel: \(channel), Value: \(safeBendValue)")
        
        // Perform the MIDI operation
        sampler.sendPitchBend(safeBendValue, onChannel: UInt8(channel))
        result(nil)
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
