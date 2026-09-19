# JNA - Keep all fields and methods for native access
-keep class com.sun.jna.** { *; }
-keepclassmembers class com.sun.jna.** { *; }
-dontwarn com.sun.jna.**

# Vosk
-keep class org.vosk.** { *; }
-keepclassmembers class org.vosk.** { *; }
