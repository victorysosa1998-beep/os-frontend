OS Flutter frontend update

This archive contains the updated Flutter `lib/` source, the supplied `pubspec.yaml`, and the referenced lightweight assets. The original uploaded frontend archive did not include the Android/iOS platform folders, so those existing folders are intentionally not replaced.

Apply it to your existing project:
1. Back up C:\Users\user\Downloads\os.
2. Extract this ZIP into C:\Users\user\Downloads\os and allow `lib/`, `pubspec.yaml`, and `assets/` to merge/overwrite.
3. Run:
   flutter pub get
   flutter analyze
   flutter run

Changes in this patch include: safer call hang-up cleanup/retries, clearer call errors, hidden-photo reveal request and owner approval popups, responsive admin/settings safe areas, clickable admin dashboard statistics, admin photo visibility, a dismissible first-run feature spotlight, custom onboarding illustrations, and swipe-to-reply quote UI for chat messages.

Important validation note: Flutter/Dart tooling was not installed in the build workspace, so this archive has not been run through `flutter analyze` or built for Android. Please run those commands in your local Flutter project before installing on a phone. Voice-note recording/playback and full reply metadata are not added in this patch; swipe-to-reply works as a quoted reply for messages returned by the current API.
