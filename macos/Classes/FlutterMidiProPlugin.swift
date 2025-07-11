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
    var noteTunes = [Int: Double]()
    var activeNotes = [Int: [Int: UInt8]]()
    
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
            
            guard let samplers = soundfontSamplers[sfId], channel < samplers.count else {
                result(FlutterError(code: "INVALID_CHANNEL", message: "Invalid channel", details: nil))
                return
            }
            
            let sampler = samplers[channel]
            
            if let tune = noteTunes[note] {
                let clampedTune = min(max(tune, -2.0), 2.0)
                let normalized = (clampedTune + 2.0) / 4.0
                let bendValue = UInt16(normalized * 16383.0)
                sampler.sendPitchBend(bendValue, onChannel: UInt8(channel))
            }
            
            if activeNotes[sfId] == nil {
                activeNotes[sfId] = [:]
            }
            activeNotes[sfId]?[note] = UInt8(channel)
            
            sampler.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
            result(nil)
            
        case "stopNote":
            let args = call.arguments as! [String: Any]
            let channel = args["channel"] as! Int
            let note = args["key"] as! Int
            let sfId = args["sfId"] as! Int
            
            guard let samplers = soundfontSamplers[sfId], channel < samplers.count else {
                result(FlutterError(code: "INVALID_CHANNEL", message: "Invalid channel", details: nil))
                return
            }
            
            let sampler = samplers[channel]
            sampler.stopNote(UInt8(note), onChannel: UInt8(channel))
            activeNotes[sfId]?.removeValue(forKey: note)
            result(nil)
            
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
            let args = call.arguments as! [String: Any]
            let sfId = args["sfId"] as! Int
            let key = args["key"] as! Int
            let tune = args["tune"] as! Double
            
            guard (0..<128).contains(key) else {
                result(FlutterError(code: "INVALID_NOTE", message: "Key must be between 0 and 127", details: nil))
                return
            }
            
            noteTunes[key] = tune
            
            if let channel = activeNotes[sfId]?[key], 
               let samplers = soundfontSamplers[sfId],
               Int(channel) < samplers.count {
                
                let sampler = samplers[Int(channel)]
                let clampedTune = min(max(tune, -2.0), 2.0)
                let normalized = (clampedTune + 2.0) / 4.0
                let bendValue = UInt16(normalized * 16383.0)
                sampler.sendPitchBend(bendValue, onChannel: channel)
            }
            
            result(nil)
            
        case "dispose":
            audioEngines.forEach { (key, value) in
                value.forEach { (audioEngine) in
                    audioEngine.stop()
                }
            }
            audioEngines = [:]
            soundfontSamplers = [:]
            soundfontURLs = [:]
            noteTunes = [:]
            activeNotes = [:]
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
