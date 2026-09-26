# google_mlkit_text_recognition references the optional Chinese, Devanagari,
# Japanese and Korean recognizer packs, which we don't bundle (the app only
# reads Latin script off IDs). Without these, R8 aborts the release build
# with "Missing class com.google.mlkit.vision.text.<script>...".
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
