import FlutterMacOS
import AVFAudio
import AVFoundation

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
    // Constants
    let NOTES_PER_OCTAVE = 12
    let CHANNELS_PER_SF = 16
    let MAX_BEND_CENTS = 200.0 // ±200 cents = ±2 semitones
    
    // Audio components
    var audioEngines: [Int: AVAudioEngine] = [:]
    var soundfontIndex = 1
    var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
    var soundfontURLs: [Int: URL] = [:]
    
    // Tuning storage: [sfId: [noteClass: tuneInCents]]
    var noteTunings = [Int: [Int: Double]]() 
    
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
            
            let audioEngine = AVAudioEngine()
            var samplers: [AVAudioUnitSampler] = []
            
            for noteClass in 0..<NOTES_PER_OCTAVE {
                let sampler = AVAudioUnitSampler()
                audioEngine.attach(sampler)
                audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)
                
                do {
                    try sampler.loadSoundBankInstrument(
                        at: url,
                        program: UInt8(program),
                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                        bankLSB: UInt8(bank)
                    )
                } catch {
                    result(FlutterError(
                        code: "SOUND_FONT_LOAD_FAILED",
                        message: "Failed to load soundfont for note class \(noteClass)",
                        details: nil
                    ))
                    return
                }
                samplers.append(sampler)
            }
            
            do {
                try audioEngine.start()
            } catch {
                result(FlutterError(
                    code: "AUDIO_ENGINE_START_FAILED",
                    message: "Failed to start audio engine",
                    details: nil
                ))
                return
            }
            
            soundfontSamplers[soundfontIndex] = samplers
            soundfontURLs[soundfontIndex] = url
            audioEngines[soundfontIndex] = audioEngine
            result(soundfontIndex)
            soundfontIndex += 1
            
        case "selectInstrument":
            let args = call.arguments as! [String: Any]
            let sfId = args["sfId"] as! Int
            let bank = args["bank"] as! Int
            let program = args["program"] as! Int
            
            guard let samplers = soundfontSamplers[sfId] else {
                result(FlutterError(code: "SYNTH_NOT_FOUND", message: "Soundfont not loaded", details: nil))
                return
            }
            
            guard let soundfontUrl = soundfontURLs[sfId] else {
                result(FlutterError(code: "SOUNDFONT_NOT_FOUND", message: "Soundfont URL not found", details: nil))
                return
            }
            
            for (noteClass, sampler) in samplers.enumerated() {
                do {
                    try sampler.loadSoundBankInstrument(
                        at: soundfontUrl,
                        program: UInt8(program),
                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                        bankLSB: UInt8(bank)
                    )
                    
                    sampler.sendProgramChange(
                        UInt8(program),
                        bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                        bankLSB: UInt8(bank),
                        onChannel: UInt8(noteClass)
                    )
                } catch {
                    result(FlutterError(
                        code: "INSTRUMENT_CHANGE_FAILED",
                        message: "Failed to change instrument for note class \(noteClass)",
                        details: nil
                    ))
                    return
                }
            }
            result(nil)
            
        case "playNote":
            let args = call.arguments as! [String: Any]
            let note = args["key"] as! Int
            let velocity = args["velocity"] as! Int
            let sfId = args["sfId"] as! Int
            
            guard let samplers = soundfontSamplers[sfId] else {
                result(FlutterError(code: "SYNTH_NOT_FOUND", message: "Soundfont not loaded", details: nil))
                return
            }
            
            let noteClass = note % NOTES_PER_OCTAVE
            let octave = note / NOTES_PER_OCTAVE
            let midiNote = UInt8(octave * NOTES_PER_OCTAVE + noteClass)
            
            if let tuneCents = noteTunings[sfId]?[noteClass] {
                applyTuning(sampler: samplers[noteClass], 
                          noteClass: noteClass,
                          tuneCents: tuneCents)
            }
            
            samplers[noteClass].startNote(midiNote, withVelocity: UInt8(velocity), onChannel: UInt8(noteClass))
            result(nil)
            
        case "stopNote":
            let args = call.arguments as! [String: Any]
            let note = args["key"] as! Int
            let sfId = args["sfId"] as! Int
            
            guard let samplers = soundfontSamplers[sfId] else {
                result(FlutterError(code: "SYNTH_NOT_FOUND", message: "Soundfont not loaded", details: nil))
                return
            }
            
            let noteClass = note % NOTES_PER_OCTAVE
            let octave = note / NOTES_PER_OCTAVE
            let midiNote = UInt8(octave * NOTES_PER_OCTAVE + noteClass)
            
            samplers[noteClass].stopNote(midiNote, onChannel: UInt8(noteClass))
            result(nil)
            
        case "unloadSoundfont":
            let args = call.arguments as! [String: Any]
            let sfId = args["sfId"] as! Int
            
            guard let audioEngine = audioEngines[sfId] else {
                result(FlutterError(code: "SOUNDFONT_NOT_FOUND", message: "Soundfont not found", details: nil))
                return
            }
            
            audioEngine.stop()
            audioEngines.removeValue(forKey: sfId)
            soundfontSamplers.removeValue(forKey: sfId)
            soundfontURLs.removeValue(forKey: sfId)
            noteTunings.removeValue(forKey: sfId)
            result(nil)
            
        case "tuneNotes":
            let args = call.arguments as! [String: Any]
            let sfId = args["sfId"] as! Int
            let key = args["key"] as! Int
            let tune = args["tune"] as! Double // Expected in cents
            
            let noteClass = key % NOTES_PER_OCTAVE
            
            if noteTunings[sfId] == nil {
                noteTunings[sfId] = [:]
            }
            noteTunings[sfId]?[noteClass] = tune
            
            // Immediately apply to the channel
            if let samplers = soundfontSamplers[sfId], noteClass < samplers.count {
                applyTuning(sampler: samplers[noteClass],
                          noteClass: noteClass,
                          tuneCents: tune)
            }
            
            result(nil)
            
        case "dispose":
            for (_, audioEngine) in audioEngines {
                audioEngine.stop()
            }
            audioEngines = [:]
            soundfontSamplers = [:]
            soundfontURLs = [:]
            noteTunings = [:]
            result(nil)
            
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func applyTuning(sampler: AVAudioUnitSampler, noteClass: Int, tuneCents: Double) {
        let clampedCents = min(max(tuneCents, -MAX_BEND_CENTS), MAX_BEND_CENTS)
        let normalized = (clampedCents + MAX_BEND_CENTS) / (2.0 * MAX_BEND_CENTS)
        let bendValue = UInt16(normalized * 16383.0)
        sampler.sendPitchBend(bendValue, onChannel: UInt8(noteClass))
    }
}
