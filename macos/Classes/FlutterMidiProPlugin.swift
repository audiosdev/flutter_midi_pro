import FlutterMacOS
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
    // Store FluidSynth instances
    var fluidSynths: [Int: UnsafeMutablePointer<fluid_synth_t>] = [:]

    // Audio engines and samplers
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

            // Create a new FluidSynth instance for this SoundFont
            let settings = new_fluid_settings()
            let synth = new_fluid_synth(settings)
            fluidSynths[soundfontIndex] = synth

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
            result(soundfontIndex - 1)

    case "tuneNotes":
            
    let args = call.arguments as! [String: Any]
    let sfId = args["sfId"] as! Int
    let key = args["key"] as! Int
    let tune = args["tune"] as! Double

    // Fetch the corresponding sampler for the provided soundfont ID
    guard let samplers = soundfontSamplers[sfId] else {
        result(FlutterError(code: "SYNTH_NOT_FOUND", message: "Soundfont not found", details: nil))
        return
    }

    // The tuning value ranges from -12.0 to 12.0 semitones, and we want to map it to a ±2 semitone range (±8192 in MIDI).
    let semitoneRange: Double = 2.0  // ±2 semitones range for MIDI pitch bend
    let maxTuneValue: Double = 12.0 // The tune value range is from -12.0 to 12.0
    let midiPitchBendMax = 8192.0  // MIDI pitch bend range is ±8192

    // Scale the tune value to fit within the MIDI pitch bend range
    let bendValue = Int32((tune / maxTuneValue) * midiPitchBendMax)  // Convert the tune value to MIDI pitch bend value
    let bendLSB = UInt8(bendValue & 0x7F)   // Least Significant Byte
    let bendMSB = UInt8((bendValue >> 7) & 0x7F)  // Most Significant Byte

    // Apply pitch bend to the specific key on each sampler channel
    for (channel, sampler) in samplers.enumerated() {
        // Send the pitch bend message for the specific key (note) to the sampler
        sampler.sendMIDIEvent(0xE0 | UInt8(channel), data1: bendLSB, data2: bendMSB)
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
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }
}
