# JNI entry points are resolved by name from the native library.
-keep class app.xrv.client.NativeBridge { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# Loaded by JNI_OnLoad through FindClass("hev/htproxy/TProxyService").
-keep class hev.htproxy.TProxyService { *; }
-keep class hev.htproxy.** { *; }

# Keep the manifest entry points and view binding.
-keep class app.xrv.client.MainActivity { *; }
-keep class app.xrv.client.AboutActivity { *; }
-keep class app.xrv.client.SettingsActivity { *; }
-keep class app.xrv.client.AppPickerActivity { *; }
-keep class app.xrv.client.LogsActivity { *; }
-keep class app.xrv.client.XrvApp { *; }
-keep class app.xrv.client.TunnelService { *; }
-keep class app.xrv.client.XrvVpnService { *; }

-keepattributes *Annotation*
-dontwarn org.json.**
