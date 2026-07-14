import 'package:bcrypt/bcrypt.dart';

/// Admin password handling. Never store or compare plaintext passwords
/// anywhere else in the app - always go through these two functions.
class PasswordUtils {
  static String hash(String plainPassword) {
    return BCrypt.hashpw(plainPassword, BCrypt.gensalt());
  }

  static bool verify(String plainPassword, String storedHash) {
    try {
      return BCrypt.checkpw(plainPassword, storedHash);
    } catch (_) {
      // storedHash was malformed/corrupted - fail closed, never fail open
      return false;
    }
  }
}