#include <jni.h>
#include <stdlib.h>
#include "libxrvbridge.h"

JNIEXPORT jstring JNICALL Java_app_xrv_client_NativeBridge_start(JNIEnv *env, jobject self, jstring config) {
    const char *raw = (*env)->GetStringUTFChars(env, config, 0);
    char *result = xrv_start_json((char *)raw);
    (*env)->ReleaseStringUTFChars(env, config, raw);
    jstring out = (*env)->NewStringUTF(env, result);
    free(result);
    return out;
}
JNIEXPORT void JNICALL Java_app_xrv_client_NativeBridge_stop(JNIEnv *env, jobject self) { xrv_stop(); }
