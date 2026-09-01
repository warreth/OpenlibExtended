# R8/ProGuard rules for OpenlibExtended.
#
# Flutter's engine and Dart code are unaffected by R8; what needs
# protecting is plugin code reached via reflection (method channels,
# JNI bridges) and JNI-exposed native glue.

# --- Flutter engine (the -keep in the flutter tool covers most of it,
# --- but pin the loader explicitly for safety on older AGP versions).
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.embedding.** { *; }

# --- sqflite: statement and database callbacks are invoked reflectively
# --- from the native side.
-keep class com.tekartik.sqflite.** { *; }

# --- flutter_inappwebview: JS-to-Dart bridges and the Java handler
# --- registry are looked up by name at runtime.
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-keepattributes JavascriptInterface
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# --- desktop_webview_window / flutter_webview windows expose platform
# --- views over method channels.
-keep class com.wethitman.desktopwebviewwindow.** { *; }

# --- url_launcher, share_plus, path_provider, package_info_plus,
# --- device_info_plus, file_picker: Pigeon-generated interfaces and
# --- event channels reference classes by name.
-keep class io.flutter.plugins.** { *; }
-keep class dev.flutter.plugins.** { *; }

# --- flutter_local_notifications: scheduled receivers restored from
# --- the system's saved intent extras.
-keep class com.dexterous.** { *; }

# --- permission_handler: result codes cross the channel as constants.
-keep class com.baseflow.** { *; }

# --- google_fonts caches descriptors via reflection on font assets.
-keep class com.google_fonts.** { *; }

# --- Generic safety net: anything invoked only from JNI or reflection
# --- keeps its name; annotations used at runtime survive too.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses,EnclosingMethod

# Don't warn about optional dependencies the plugins reference only
# on some platforms; absence at runtime is handled by the plugins.
-dontwarn javax.annotation.**
-dontwarn com.google.errorprone.annotations.**
