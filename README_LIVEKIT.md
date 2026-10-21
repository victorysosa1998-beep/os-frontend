# OS Flutter frontend — LiveKit call integration

Run `flutter pub get` after merging this source into the existing Flutter project. `livekit_client: ^2.13.1` is now included in `pubspec.yaml`.

Use `flutter run --dart-define=OS_API_URL=https://YOUR-BACKEND-DOMAIN` to point the app at the deployed backend. For a physical phone on the same Wi-Fi as a local backend, use the computer's LAN IP (not `localhost`).

Changes include:
- Signup prompts for email OTP verification if the backend successfully sends the code.
- Resend-code and password-reset endpoints are used by the existing auth/settings UI.
- Chat audio/video buttons create LiveKit calls rather than Jitsi links.
- In-app incoming call prompt with Accept/Decline while OS is open.
- Live call UI with mute, camera toggle, speaker routing, connection retry and end-call controls.

Add permissions from `ANDROID_MANIFEST_PERMISSIONS.xml` under `<manifest>` in the existing `android/app/src/main/AndroidManifest.xml`. On iOS, add camera/microphone usage descriptions to `ios/Runner/Info.plist`.

The uploaded source snapshot does not include the generated `android/`, `ios/`, or platform build directories, so merge these source files into the existing Flutter project rather than replacing the whole Flutter project directory. Run `flutter analyze` and test on two real devices before release. Background/terminated incoming calls are not implemented; this version polls in-app while the app is open.


## Firebase Cloud Messaging (push notifications)

- This source now registers the signed-in device's FCM token with `POST /devices/push-token`.
- FastAPI sends a high-priority FCM notification when `/calls/invite` creates a call. Firebase is used only for push delivery; OS authentication, database, and call permissions remain in FastAPI.
- Run `dart pub global activate flutterfire_cli` and `flutterfire configure` from this Flutter project. Select Android (and iOS if you ship it). This generates `lib/firebase_options.dart`; it is intentionally not included because it contains project-specific Firebase configuration.
- The backend needs a Firebase Admin service-account JSON file. Set `FIREBASE_SERVICE_ACCOUNT_PATH` to its path in `.env`; never put that file in Flutter, Git, or a public download.
- Android manifest needs the default channel metadata `com.google.firebase.messaging.default_notification_channel_id` set to `os_calls`, and `android.permission.POST_NOTIFICATIONS` for Android 13+. See the setup guide.
- When OS is open, incoming calls use the existing in-app Accept/Decline dialog. When backgrounded, Android/iOS displays the push notification; tapping it opens OS and the app fetches the pending call from FastAPI. A notification is not a guarantee of a full-screen native call UI on every device; force-stop, iOS force-quit, denied permission, OEM battery policies, and connectivity can block delivery.
