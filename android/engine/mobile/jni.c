/*
 * JNI entry points for the XRV Android client.
 *
 * These live in the same shared object as the Go engine so the APK ships a
 * single, self-contained native library.  The previous design linked a second
 * JNI shim against the engine by absolute build path, which made the loader
 * abort the whole process on a real device.
 *
 * Both functions below only translate JNI strings; all protocol work remains
 * in Go and no configuration is ever written to a log.
 *
 * The Android NDK compiler defines __ANDROID__.  Other hosts compile this
 * translation unit as empty so `go test ./...` can still exercise the engine
 * without an NDK/JNI include path.
 */

#ifdef __ANDROID__

#include <jni.h>
#include <stddef.h>
#include <stdlib.h>

extern char *xrv_start_json(char *raw);
extern void xrv_stop(void);
extern char *xrv_stats_json(void);
extern char *xrv_probe_edges_json(char *raw);
extern char *xrv_test_connection_json(char *raw);
extern char *xrv_logs_text(void);
extern void xrv_logs_clear(void);

JNIEXPORT jstring JNICALL
Java_app_xrv_client_NativeBridge_start(JNIEnv *env, jobject self, jstring config)
{
    const char *raw;
    char *result;
    jstring out;

    (void) self;
    if (config == NULL)
        return NULL;

    raw = (*env)->GetStringUTFChars(env, config, NULL);
    if (raw == NULL)
        return NULL;

    result = xrv_start_json((char *) raw);
    (*env)->ReleaseStringUTFChars(env, config, raw);

    if (result == NULL)
        return NULL;

    out = (*env)->NewStringUTF(env, result);
    free(result);
    return out;
}

JNIEXPORT void JNICALL
Java_app_xrv_client_NativeBridge_stop(JNIEnv *env, jobject self)
{
    (void) env;
    (void) self;
    xrv_stop();
}

JNIEXPORT jstring JNICALL
Java_app_xrv_client_NativeBridge_stats(JNIEnv *env, jobject self)
{
    char *result;
    jstring out;

    (void) self;
    result = xrv_stats_json();
    if (result == NULL)
        return NULL;
    out = (*env)->NewStringUTF(env, result);
    free(result);
    return out;
}

static jstring
call_with_json(JNIEnv *env, jstring input, char *(*call)(char *))
{
    const char *raw;
    char *result;
    jstring out;

    if (input == NULL)
        return NULL;
    raw = (*env)->GetStringUTFChars(env, input, NULL);
    if (raw == NULL)
        return NULL;
    result = call((char *) raw);
    (*env)->ReleaseStringUTFChars(env, input, raw);
    if (result == NULL)
        return NULL;
    out = (*env)->NewStringUTF(env, result);
    free(result);
    return out;
}

JNIEXPORT jstring JNICALL
Java_app_xrv_client_NativeBridge_probeEdges(JNIEnv *env, jobject self, jstring input)
{
    (void) self;
    return call_with_json(env, input, xrv_probe_edges_json);
}

JNIEXPORT jstring JNICALL
Java_app_xrv_client_NativeBridge_testConnection(JNIEnv *env, jobject self, jstring input)
{
    (void) self;
    return call_with_json(env, input, xrv_test_connection_json);
}

JNIEXPORT jstring JNICALL
Java_app_xrv_client_NativeBridge_logs(JNIEnv *env, jobject self)
{
    char *result;
    jstring out;

    (void) self;
    result = xrv_logs_text();
    if (result == NULL)
        return NULL;
    out = (*env)->NewStringUTF(env, result);
    free(result);
    return out;
}

JNIEXPORT void JNICALL
Java_app_xrv_client_NativeBridge_clearLogs(JNIEnv *env, jobject self)
{
    (void) env;
    (void) self;
    xrv_logs_clear();
}

#endif /* __ANDROID__ */
