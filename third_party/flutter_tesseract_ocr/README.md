# Vendored: flutter_tesseract_ocr

This is a local, Android-only copy of [`flutter_tesseract_ocr`
0.4.31](https://pub.dev/packages/flutter_tesseract_ocr), used for the
OCR fallback in [`../../lib/services/pdf_extractor.dart`](../../lib/services/pdf_extractor.dart).

## Why vendored instead of a normal pub.dev dependency

The published package's `android/build.gradle` opens with its own
`buildscript { repositories { google(); jcenter() } ... }` block that
declares a private copy of the Android Gradle Plugin for just that one
module. Two problems, both fatal on this project's toolchain (Gradle/AGP
new enough to use centralized plugin management, see `android/settings.gradle`):

1. `jcenter()` shut down years ago and current Gradle has dropped the
   `jcenter()` repository method entirely - the build fails immediately
   with `Could not find method jcenter()`.
2. Even with that fixed, a per-module `buildscript` classpath conflicts
   with Flutter's centrally-applied AGP, producing a second failure
   (`'kotlin-android' plugin requires one of the Android Gradle plugins`).

The underlying OCR engine (Tesseract4Android, bundled here as
`android/libs/tesseract4android-release.aar`) and the plugin's actual Java
glue code (`FlutterTesseractOcrPlugin.java`) are both fine - only the
outer Gradle wiring was stale. `android/build.gradle` in this folder
deletes the broken `buildscript` block and lets the module use the AGP
version Flutter already applies at the root; everything else is
unchanged upstream source. Diff against the pub.dev package if you want
to confirm that's the only change.

Kept in the repo (not patched into the pub cache) so the fix is
reproducible on any machine that clones this project - a pub cache edit
would not survive a fresh `flutter pub get` elsewhere, which matters for
a build that needs to be reproducible at the thesis defense.

## License

`LICENSE` in this folder is the original package's license, copied
alongside the vendored source.
