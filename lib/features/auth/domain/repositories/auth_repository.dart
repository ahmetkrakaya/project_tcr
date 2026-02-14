import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/failures.dart';
import '../entities/user_entity.dart';

/// Auth Repository Interface
abstract class AuthRepository {
  /// Auth state changes stream
  Stream<AuthState> get authStateChanges;

  /// Sign in with email and password
  Future<({UserEntity? user, Failure? failure})> signInWithEmail(
    String email,
    String password,
  );

  /// Sign up with email and password
  /// Returns null user if email verification is required
  Future<({UserEntity? user, Failure? failure})> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  /// Verify email with OTP code
  Future<({UserEntity? user, Failure? failure})> verifyEmail(String email, String token);

  /// Resend verification email
  Future<Failure?> resendVerificationEmail(String email);

  /// Reset password (redirectTo: e-posta linkinin açılacağı URL, mobilde deep link)
  Future<Failure?> resetPassword(String email, {String? redirectTo});

  /// Yeni şifre belirle (şifre sıfırlama linkinden sonra)
  Future<Failure?> updatePassword(String newPassword);

  /// Sign out
  Future<Failure?> signOut();

  /// Get current user
  Future<({UserEntity? user, Failure? failure})> getCurrentUser();

  /// Update user profile
  Future<({UserEntity? user, Failure? failure})> updateProfile({
    String? firstName,
    String? lastName,
    String? phone,
    String? bloodType,
    String? tshirtSize,
    String? shoeSize,
    String? bio,
    String? gender,
    String? birthDate,
    double? weight,
  });

  /// Get ICE card
  Future<({IceCardEntity? iceCard, Failure? failure})> getIceCard(String userId);

  /// Update ICE card
  Future<({IceCardEntity? iceCard, Failure? failure})> updateIceCard({
    String? chronicDiseases,
    String? medications,
    String? allergies,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? additionalNotes,
  });

  /// Email'in zaten kayıtlı olup olmadığını kontrol et
  Future<bool> checkEmailExists(String email);
}
