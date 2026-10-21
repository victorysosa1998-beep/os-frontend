
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'OS_API_URL',
    defaultValue: 'https://os-backend-cod3.onrender.com',
  );
}
