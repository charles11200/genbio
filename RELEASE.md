# Building BioQuest for sharing

The APK you hand to another student must be a **release** build. Debug
builds (`flutter build apk --debug`, or anything `flutter run` installs)
are for development only and are the reason a shared app misbehaves.

## The one command

```bash
flutter build apk --release --target-platform android-arm,android-arm64
```

Output: `build/app/outputs/flutter-apk/app-release.apk` (~50 MB)

Send that file by ShareIt, Bluetooth, USB, whatever - it is self-contained
and needs no internet on the receiving phone.

## Why not the debug APK

| | debug | release |
|---|---|---|
| INTERNET permission | **yes** - added by `android/app/src/debug/AndroidManifest.xml` for hot reload | **no** |
| Size | ~110 MB | ~50 MB |
| Speed | JIT, slow first frames | AOT compiled |
| Signing | debug key, changes per machine | your `bioquest-release.jks` |
| Debug banner | yes | no |

The INTERNET permission line matters for this project specifically: the
thesis claims a fully offline app, and a debug build silently contradicts
that. Only the release build actually ships with zero network permission.

## What the release build guarantees

Verified with
`aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk`:

- **Permissions requested: none.** (`DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
  is an app-scoped internal permission AndroidX declares for its own
  runtime receivers; it grants no access to anything and is not shown to
  the user.)
- **minSdkVersion 24** (Android 7.0) - installs on essentially any phone
  still in use.
- **ABIs: arm64-v8a + armeabi-v7a** - one file that runs on every real
  Android phone, old or new. x86/x86_64 are stripped (emulator-only, and
  they cost ~9 MB of TensorFlow Lite libraries nothing would load).
- **Signed** with `CN=BioQuest` (APK Signature Scheme v2).

Three permissions used to appear here that nobody asked for -
`READ_PHONE_STATE`, `READ_EXTERNAL_STORAGE`, `WRITE_EXTERNAL_STORAGE`.
They were *implied*, not requested: the bundled `org.tensorflow.lite.gpu.api`
AAR declares no `targetSdkVersion`, so the manifest merger treated it as
pre-API-4 legacy code and auto-granted it the old broad permissions.
`android/app/src/main/AndroidManifest.xml` now strips them with
`tools:node="remove"`. Re-check with the `aapt2` command above after any
dependency upgrade.

## Installing on the receiving phone

Sideloaded apps are blocked by default. On the other student's phone:

1. Open the received `.apk`.
2. Android will say installs from this source are not allowed - tap
   **Settings** and enable it for whichever app delivered the file
   (ShareIt, Files, Chrome...).
3. Play Protect may warn that the app is unrecognised. That is expected
   for any app not distributed through the Play Store - tap **Install
   anyway**. It is not a sign of a problem with the APK.

If install fails with a bare **"App not installed"**, the usual causes are:

- an older BioQuest signed with a *different* key is still installed -
  uninstall it first;
- the file was truncated in transfer - resend it;
- the phone is 32-bit and running out of space - the APK needs ~50 MB free
  plus room to expand.

## Signing key

`android/bioquest-release.jks` + `android/key.properties` are gitignored
and are **not** in this repo. Back them up somewhere safe. If you lose
them you can still build, but the new APK will have a different signature,
so everyone must uninstall the old BioQuest before installing the new one.

## Version bumps

Before distributing an update, raise both values in
`android/app/build.gradle.kts`:

```kotlin
versionCode = 2        // must increase, or Android refuses the upgrade
versionName = "1.1.0"  // what the user sees
```
