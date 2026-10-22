# OS Dating production release setup

## Production Android application ID

The app now uses `com.sosatechnologies.osdating`. This is a proposed production identifier based on the SosaTechnologies brand; confirm that you control the associated namespace before publishing. Once an app is published on Google Play, its application ID cannot be changed for that listing.

## Firebase registration is required after changing the ID

The included `android/app/google-services.json` was updated only so the Google Services Gradle plugin can select the Android client. Its Firebase Android app ID is still the existing registration (`1:286746227754:android:dfca423bc00cea46c03f53`) created for the old package. In Firebase Console, add/register an Android app with package `com.sosatechnologies.osdating`, download its new `google-services.json`, and replace the included file. Add the SHA fingerprints for the release/upload key if required by Firebase Auth or other Google APIs. Do not publish until this is done and push notifications are tested. The iOS bundle ID was also changed in source; register the matching iOS app and regenerate `GoogleService-Info.plist` / FlutterFire options if you ship iOS.

## Release signing (required)

The release build no longer falls back to debug signing. Create and securely back up a private upload keystore locally, outside source control and outside shared ZIPs. Set these environment variables in the release shell/CI:

- `OS_UPLOAD_STORE_FILE` — absolute or project-relative path to the keystore file
- `OS_UPLOAD_STORE_PASSWORD`
- `OS_UPLOAD_KEY_ALIAS`
- `OS_UPLOAD_KEY_PASSWORD`

Keep passwords and the keystore private. Enrol in Play App Signing when Play Console prompts you. A release bundle should not be produced for publishing until signing is configured.

## API and backend

The Flutter client currently points to `https://os-backend-cod3.onrender.com` in `lib/config.dart`. Confirm that this is the production API and that it serves HTTPS, has durable database storage, and has all secrets set through the host's environment variables. The supplied backend implements server-side 18+ signup validation, account deletion at `DELETE /me/account`, and block/report endpoints. Verify these on the deployed instance, including deletion of associated media in object storage; the account deletion code shown in the supplied backend deletes database records but does not visibly remove media objects from external storage.

## Google Play items that cannot be completed by editing source files

Before submission: register the new Firebase app; configure upload signing; build and test a release AAB; verify current target API requirement in Play Console; publish a real privacy policy at a stable HTTPS URL; provide a working public account-deletion request URL and test the entire process; configure Data safety, content rating, app access, ads, target audience and store listing; test reports/blocks and moderation; and run Play pre-launch report. The privacy-policy draft is not itself a hosted policy. Do not claim compliance until each item is verified.

## Build verification status

This workspace did not have the Flutter SDK installed, so `flutter analyze`, automated Flutter tests and an Android release build could not be run here. Run those checks in the project environment before release.
