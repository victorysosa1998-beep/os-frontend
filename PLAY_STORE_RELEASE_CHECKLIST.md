# Google Play release readiness checklist — OS Dating

This is a working checklist, not a certification of Play compliance. Google Play Console declarations and real deployment tests are still required.

## Source changes made in this archive
- [x] Changed Android namespace/application ID to `com.sosatechnologies.osdating` (confirm you control this identifier before first publication).
- [x] Removed the release build's automatic debug-signing fallback; release signing is configured using `OS_UPLOAD_*` environment variables.
- [x] Updated Google Services client package selector and iOS bundle ID in source. **Firebase registrations/configuration must still be regenerated in Firebase Console for the new IDs.**
- [x] Disabled Android app backup and cleartext HTTP traffic in the main application manifest.
- [x] Bumped app version to `1.0.1+2`.
- [x] Set Android target SDK to API 36 (verify against the Play Console requirement in force on submission day).
- [x] Reviewed supplied backend: signup validates age 18+ server-side; authenticated account deletion endpoint exists; block/report endpoints exist.

## Required before publication
- [ ] Register Android app ID `com.sosatechnologies.osdating` in Firebase; replace `android/app/google-services.json` with the newly downloaded file and test FCM/auth integrations.
- [ ] If shipping iOS, register matching iOS bundle ID and regenerate iOS Firebase config/FlutterFire options.
- [ ] Create and privately back up an upload keystore; set all four `OS_UPLOAD_*` variables; enroll in Play App Signing.
- [ ] Confirm the current Play target API requirement and inspect the merged manifest/AAB.
- [ ] Host a complete, accurate privacy policy on a public HTTPS URL and enter it in Play Console and in the app.
- [ ] Provide a working public web account-deletion request URL. Test end-to-end deletion, including external media/object storage, and verify that the request route is monitored/processed.
- [ ] Complete Data safety accurately for backend, Firebase Messaging, LiveKit, storage, location, photos/videos, voice notes, and other services actually used.
- [ ] Complete store listing, contact details, app access/reviewer instructions, content rating, target audience, ads declaration, and applicable dating/social app declarations.
- [ ] Test reporting, blocking, content moderation, user support, and admin review workflows on the deployed backend.
- [ ] Test permission prompts and denial paths for location, camera, microphone, notifications, and biometrics.
- [ ] Run `flutter analyze`, all tests, a clean release AAB build, and Play pre-launch report on a machine with the Flutter/Android toolchain.

## Backend-specific caution

The supplied backend's `/me/account` handler deletes database records, posts, conversations, reports, and verification rows, but the inspected code does not visibly delete media objects from external object storage. Confirm and implement that cleanup before promising complete erasure. Do not treat an in-app delete button alone as proof of the public web deletion requirement.
