# OS Dating

Flutter client for OS Dating (verification-first, adults-only dating app).

## Development

- Install the Flutter SDK compatible with the Dart constraint in `pubspec.yaml`.
- Run `flutter pub get`, then `flutter analyze` and the test suite.
- Configure Firebase for your own project and verify platform configuration before running.

## Google Play release

Read [`PLAY_STORE_RELEASE_CHECKLIST.md`](PLAY_STORE_RELEASE_CHECKLIST.md) before preparing a Play release. [`PRIVACY_POLICY_DRAFT.md`](PRIVACY_POLICY_DRAFT.md) is an unapproved draft and must be verified, completed, and hosted publicly before use. This repository cannot complete Play Console declarations, provide a production signing key, verify backend deletion/moderation behavior, or guarantee approval.


## Production release

See `RELEASE_SETUP.md` and `PLAY_STORE_RELEASE_CHECKLIST.md` before building or submitting to Google Play. Firebase registration and private release signing must be completed outside this source archive.
