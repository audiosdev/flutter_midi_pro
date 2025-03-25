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

            guard let synth = fluidSynths[sfId] else {
                result(FlutterError(code: "SYNTH_NOT_FOUND", message: "FluidSynth instance not found", details: nil))
                return
            }

            var noteTunings = [Float](repeating: 0.0, count: 128) // Default tuning (no change)
            noteTunings[key] = Float(tune) // Apply tuning offset for the specific note

            let tuningName = "custom_tuning"
            fluid_synth_tune_notes(synth, 0, tuningName, &noteTunings, 128)

            fluid_synth_activate_tuning(synth, 0, 0, 1)  // Activate tuning on Channel 0
            fluid_synth_activate_tuning(synth, 14, 0, 1) // Activate tuning on Channel 14
            fluid_synth_activate_tuning(synth, 15, 0, 1) // Activate tuning on Channel 15

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
