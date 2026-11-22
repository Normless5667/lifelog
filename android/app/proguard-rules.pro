# google_mlkit_text_recognition references optional non-Latin script options in switch().
# LifeLog only uses TextRecognitionScript.latin (supports English & Vietnamese natively).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Keep ML Kit, GMS ML Kit internals, VisionKit JNI bridge, DataTransport, Firebase Components/Encoders,
# and Flutter ML Kit plugin bridges so R8 does not strip, rename, or class-merge reflection/DI targets.
-keep class com.google.mlkit.** { *; }
-keep class com.google.mlkit.common.internal.** { *; }
-keep class com.google.mlkit.vision.common.internal.** { *; }
-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.common.sdkinternal.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_text_common.** { *; }
-keep class com.google.android.libraries.vision.visionkit.** { *; }
-keep class com.google.android.datatransport.** { *; }
-keep class com.google.firebase.components.** { *; }
-keep class com.google.firebase.encoders.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class io.flutter.plugin.common.** { *; }

-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
