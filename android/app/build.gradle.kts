import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the source tree in
// android/key.properties (see android/key.properties.example). A release
// APK MUST be signed - an unsigned one is rejected by Android at install
// time with a bare "App not installed", which is exactly what happens when
// you hand the file to a classmate.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
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
        // 24 = Android 7.0, via Flutter's own default. Covers the
        // overwhelming majority of phones still in use, so a classmate on
        // an older handset can still install this.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        // Ship only the two ARM ABIs every real Android phone uses. x86_64
        // exists for emulators and a few Intel Chromebooks, and costs ~9 MB
        // of TensorFlow Lite native libraries no student's handset will
        // ever load.
        //
        // This must live in defaultConfig, not buildTypes.release - setting
        // it there is silently ignored, because Flutter's Gradle plugin
        // contributes the engine's native libs after the build type is
        // configured. Note this also drops x86 from debug builds, so an
        // Intel emulator can no longer run the app; testing here is on a
        // physical ARM device anyway.
        //
        // Pair with `--target-platform android-arm,android-arm64` on the
        // build command: this filter covers the plugin AARs, that flag
        // covers Flutter's own engine libs. Neither alone is enough.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }

    // Belt-and-braces to defaultConfig's abiFilters: the TensorFlow Lite
    // AAR's own .so files are contributed by the Flutter Gradle plugin late
    // enough that abiFilters alone still leaves lib/x86_64/*.so in the APK
    // (~9 MB of libtensorflowlite_jni + libdartjni that no phone loads).
    // Excluding at packaging time is the step that actually drops them.
    packaging {
        jniLibs {
            excludes += setOf("lib/x86/**", "lib/x86_64/**")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fail loudly at install time rather than silently shipping
                // a debug-signed build: without key.properties there is no
                // release key to use.
                signingConfigs.getByName("debug")
            }
            // Left off deliberately. R8/ProGuard strips classes it can't
            // see being used, and tflite_flutter reaches its native
            // interpreter reflectively - shrinking it has historically
            // broken TFLite model loading at runtime, which would silently
            // disable the distractor ranking only in release builds.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
