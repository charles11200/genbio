plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.genbio"
    // Bumped from 35: flutter_plugin_android_lifecycle, sqflite_android, and
    // tflite_flutter all require compileSdk 36 - compiling against a higher
    // SDK than targetSdk is backward compatible, per Flutter's own guidance.
    compileSdk = 36
    // tflite_flutter pulls in the `jni` package, which needs this NDK
    // version specifically (the AGP-default 27.x isn't enough for it).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.genbio"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }
}

flutter {
    source = "../.."
}
