# OS Flutter app — Windows setup

## Requirements
- Flutter stable SDK and Android Studio (Android SDK + platform tools)
- Android phone with USB debugging, or Android emulator
- Python backend ZIP extracted separately and running on the same PC/network

## 1. Create Android/iOS platform folders and install the exact launcher icon
Open PowerShell in the extracted Flutter package folder and run:
```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\setup_flutter.ps1
```
This runs `flutter create --platforms=android,ios .`, `flutter pub get`, adds Android/iOS permission declarations, and generates launcher icons from `flutter_app/assets/icon/os_launcher.png`. The supplied `assets/os_logo.svg` and `os_launcher.png` are preserved; do not replace or edit them if you want the exact same logo.

For Android only, the iOS platform generation can be omitted by changing the command to `flutter create --platforms=android .` in `setup_flutter.ps1`.

## 2. Start the Python API first
Use the backend package instructions. Check `http://127.0.0.1:8000/health` from the PC.

## 3. Run the app
From `flutter_app`:

Android emulator:
```powershell
flutter run --dart-define=OS_API_URL=http://10.0.2.2:8000
```

Physical Android phone on same Wi-Fi:
```powershell
ipconfig
# Use the PC's IPv4 address, then:
flutter run --dart-define=OS_API_URL=http://192.168.1.20:8000
```
Replace the example IP with the actual PC LAN IP. Allow Python/port 8000 through Windows Firewall on a private network. Do not expose this development server directly to the public internet.

## 4. Build an APK
```powershell
flutter build apk --release --dart-define=OS_API_URL=https://YOUR-HTTPS-API-DOMAIN
```
Install at `build\app\outputs\flutter-apk\app-release.apk`.

## Notes
- `flutter create` generates platform folders; they are intentionally not bundled to keep the source package small and avoid stale generated platform files.
- Launcher generation requires network access for first-time dependency resolution.
- A launcher icon being present does not mean the backend or app has passed store-release/security certification.
