#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>

define PLAYER_COUNT 84
fluid_settings_t* settings = new_fluid_settings();
std::map<int, fluid_synth_t*> synths = {};
std::map<int, fluid_audio_driver_t*> drivers = {};
std::map<int, int> soundfonts = {};
int nextSfId = 1;
static double mNoteTunes[PLAYER_COUNT];

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    fluid_settings_setnum(settings, "synth.gain", 1.0);
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    synths[nextSfId] = new_fluid_synth(settings);
    drivers[nextSfId] = new_fluid_audio_driver(settings, synths[nextSfId]);
    int sfId = fluid_synth_sfload(synths[nextSfId], nativePath, 0);
    for (int i = 0; i < 16; i++) {
        fluid_synth_program_select(synths[nextSfId], i, sfId, bank, program);
    }
    env->ReleaseStringUTFChars(path, nativePath);
    soundfonts[nextSfId] = sfId;
    nextSfId++;
    return nextSfId - 1;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity, jint sfId) {
    fluid_synth_noteon(synths[sfId], channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint sfId) {
    fluid_synth_noteoff(synths[sfId], channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId) {
    delete_fluid_audio_driver(drivers[sfId]);
    delete_fluid_synth(synths[sfId]);
    synths.erase(sfId);
    drivers.erase(sfId);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    for (auto const& x : synths) {
        delete_fluid_audio_driver(drivers[x.first]);
        delete_fluid_synth(synths[x.first]);
    }
    synths.clear();
    drivers.clear();
    soundfonts.clear();
    delete_fluid_settings(settings);
}

extern "C" JNIEXPORT
void JNICALL Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_tuneNotes(JNIEnv *jEnv, jclass type,
                                                                          jint key, jdouble tune) {
    mNoteTunes[key] = tune;

    fluid_synth_activate_octave_tuning(synths[sfId], 0, 0, "tuning", mNoteTunes, 1);
    fluid_synth_activate_tuning(synths[sfId], 14, 0, 0, 1);
    fluid_synth_activate_tuning(synths[sfId], 15, 0, 0, 1);
}
