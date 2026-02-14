import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';

/// Auth Repository Implementation
class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource _remoteDataSource;

  AuthRepositoryImpl({required AuthRemoteDataSource remoteDataSource})
      : _remoteDataSource = remoteDataSource;

  @override
  Stream<AuthState> get authStateChanges => _remoteDataSource.authStateChanges;

  @override
  Future<({UserEntity? user, Failure? failure})> signInWithEmail(
    String email,
    String password,
  ) async {
    try {
      final userModel = await _remoteDataSource.signInWithEmail(email, password);
      final roles = await _remoteDataSource.getUserRoles(userModel.id);
      return (user: userModel.toEntity(roles: roles), failure: null);
    } on AppAuthException catch (e) {
      return (
        user: null,
        failure: AuthFailure(message: e.message, code: e.code)
      );
    } catch (e) {
      return (
        user: null,
        failure: AuthFailure(
          message: 'Giriş başarısız',
          originalError: e,
        )
      );
    }
  }

  @override
  Future<({UserEntity? user, Failure? failure})> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      final userModel = await _remoteDataSource.signUpWithEmail(
        email: email,
        password: password,
        firstName: firstName,
        lastName: lastName,
      );
      
      // Email doğrulama bekleniyorsa null döndür
      if (userModel == null) {
        return (user: null, failure: null);
      }
      
      final roles = await _remoteDataSource.getUserRoles(userModel.id);
      return (user: userModel.toEntity(roles: roles), failure: null);
    } on AppAuthException catch (e) {
      return (
        user: null,
        failure: AuthFailure(message: e.message, code: e.code)
      );
    } catch (e) {
      return (
        user: null,
        failure: AuthFailure(
          message: 'Kayıt başarısız',
          originalError: e,
        )
      );
    }
  }

  @override
  Future<({UserEntity? user, Failure? failure})> verifyEmail(String email, String token) async {
    try {
      final userModel = await _remoteDataSource.verifyEmail(email, token);
      final roles = await _remoteDataSource.getUserRoles(userModel.id);
      return (user: userModel.toEntity(roles: roles), failure: null);
    } on AppAuthException catch (e) {
      return (
        user: null,
        failure: AuthFailure(message: e.message, code: e.code)
      );
    } catch (e) {
      return (
        user: null,
        failure: AuthFailure(
          message: 'Email doğrulama başarısız',
          originalError: e,
        )
      );
    }
  }

  @override
  Future<Failure?> resendVerificationEmail(String email) async {
    try {
      await _remoteDataSource.resendVerificationEmail(email);
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(message: e.message, code: e.code);
    } catch (e) {
      return AuthFailure(
        message: 'Doğrulama emaili gönderilemedi',
        originalError: e,
      );
    }
  }

  @override
  Future<Failure?> resetPassword(String email, {String? redirectTo}) async {
    try {
      await _remoteDataSource.resetPassword(email, redirectTo: redirectTo);
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(message: e.message, code: e.code);
    } catch (e) {
      return AuthFailure(
        message: 'Şifre sıfırlama başarısız',
        originalError: e,
      );
    }
  }

  @override
  Future<Failure?> updatePassword(String newPassword) async {
    try {
      await _remoteDataSource.updatePassword(newPassword);
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(message: e.message, code: e.code);
    } catch (e) {
      return AuthFailure(
        message: 'Şifre güncellenemedi',
        originalError: e,
      );
    }
  }

  @override
  Future<Failure?> signOut() async {
    try {
      await _remoteDataSource.signOut();
      return null;
    } on AppAuthException catch (e) {
      return AuthFailure(message: e.message, code: e.code);
    } catch (e) {
      return AuthFailure(message: 'Çıkış başarısız', originalError: e);
    }
  }

  @override
  Future<({UserEntity? user, Failure? failure})> getCurrentUser() async {
    try {
      final userModel = await _remoteDataSource.getCurrentUser();
      if (userModel == null) {
        return (user: null, failure: null);
      }
      final roles = await _remoteDataSource.getUserRoles(userModel.id);
      return (user: userModel.toEntity(roles: roles), failure: null);
    } catch (e) {
      return (user: null, failure: null);
    }
  }

  @override
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
  }) async {
    try {
      final data = <String, dynamic>{};
      if (firstName != null) data['first_name'] = firstName;
      if (lastName != null) data['last_name'] = lastName;
      if (phone != null) data['phone'] = phone;
      if (bloodType != null) data['blood_type'] = bloodType;
      if (tshirtSize != null) data['tshirt_size'] = tshirtSize;
      if (shoeSize != null) data['shoe_size'] = shoeSize;
      if (bio != null) data['bio'] = bio;
      if (gender != null) data['gender'] = gender;
      if (birthDate != null) data['birth_date'] = birthDate;
      if (weight != null) data['weight_kg'] = weight;

      final userModel = await _remoteDataSource.updateProfile(data);
      final roles = await _remoteDataSource.getUserRoles(userModel.id);
      return (user: userModel.toEntity(roles: roles), failure: null);
    } on ServerException catch (e) {
      return (
        user: null,
        failure: ServerFailure(message: e.message, code: e.code)
      );
    } catch (e) {
      return (
        user: null,
        failure: ServerFailure(
          message: 'Profil güncellenemedi',
          originalError: e,
        )
      );
    }
  }

  @override
  Future<({IceCardEntity? iceCard, Failure? failure})> getIceCard(
      String userId) async {
    try {
      final iceCardModel = await _remoteDataSource.getIceCard(userId);
      return (iceCard: iceCardModel?.toEntity(), failure: null);
    } catch (e) {
      return (iceCard: null, failure: null);
    }
  }

  @override
  Future<({IceCardEntity? iceCard, Failure? failure})> updateIceCard({
    String? chronicDiseases,
    String? medications,
    String? allergies,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? additionalNotes,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (chronicDiseases != null) data['chronic_diseases'] = chronicDiseases;
      if (medications != null) data['medications'] = medications;
      if (allergies != null) data['allergies'] = allergies;
      if (emergencyContactName != null) {
        data['emergency_contact_name'] = emergencyContactName;
      }
      if (emergencyContactPhone != null) {
        data['emergency_contact_phone'] = emergencyContactPhone;
      }
      if (emergencyContactRelation != null) {
        data['emergency_contact_relation'] = emergencyContactRelation;
      }
      if (additionalNotes != null) data['additional_notes'] = additionalNotes;

      final iceCardModel = await _remoteDataSource.upsertIceCard(data);
      return (iceCard: iceCardModel.toEntity(), failure: null);
    } on ServerException catch (e) {
      return (
        iceCard: null,
        failure: ServerFailure(message: e.message, code: e.code)
      );
    } catch (e) {
      return (
        iceCard: null,
        failure: ServerFailure(
          message: 'ICE kartı kaydedilemedi',
          originalError: e,
        )
      );
    }
  }

  @override
  Future<bool> checkEmailExists(String email) async {
    return await _remoteDataSource.checkEmailExists(email);
  }
}
