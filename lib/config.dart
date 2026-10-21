class AppConfig {
  // OS backend running on your laptop; phone and laptop use the same Wi-Fi.
  static const apiBaseUrl = String.fromEnvironment(
    'OS_API_URL',
    defaultValue: 'http://192.168.18.8:8000',
  );
}
// sosa