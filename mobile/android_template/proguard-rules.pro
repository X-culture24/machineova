# Installed by setup.sh. Release builds are minified with R8.
# ML Kit text recognition: only the Latin model is bundled (ID cards). The plugin still
# references the optional Chinese/Devanagari/Japanese/Korean recognisers — they are absent on purpose.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ML Kit creates its components (VisionCommonRegistrar, TextRegistrar, BarcodeRegistrar, …) by
# reflection at start-up. Without these rules R8 strips their constructors and, in release builds
# only, every text / barcode recognition call fails — the ID scanner shows the camera but never
# reads a number.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keepclassmembers class * { @com.google.firebase.components.** *; }
