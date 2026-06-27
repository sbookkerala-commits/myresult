# Flutter-specific ProGuard rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# SQLite / plugins used in release builds
-keep class com.tekartik.sqflite.** { *; }
-keep class androidx.sqlite.** { *; }
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# Keep our app classes if needed, though usually not necessary for standard Flutter apps
-keep class com.example.myresult.** { *; }

# Syncfusion PDF (Dear result parse in release)
-keep class com.syncfusion.** { *; }
-dontwarn com.syncfusion.**
-repackageclasses ''
-allowaccessmodification
-overloadaggressively
