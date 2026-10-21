import 'package:local_auth/local_auth.dart';

/// Uses the device's operating-system biometric prompt. OS Dating never receives
/// or stores fingerprint images/templates; Android/iOS handle biometric matching.
class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      final biometrics = await _auth.getAvailableBiometrics();
      return supported && canCheck && biometrics.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'Verify your identity to sign in to OS Dating'}) async {
    try {
      if (!await isAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}
