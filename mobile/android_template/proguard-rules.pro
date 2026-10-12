# Installed by setup.sh. Release builds are minified with R8.
# ML Kit text recognition: only the Latin model is bundled (ID cards). The plugin still
# references the optional Chinese/Devanagari/Japanese/Korean recognisers — they are absent on purpose.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
