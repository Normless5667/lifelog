# google_mlkit_text_recognition references optional non-Latin script options in switch().
# LifeLog only uses TextRecognitionScript.latin (supports English & Vietnamese natively).
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
