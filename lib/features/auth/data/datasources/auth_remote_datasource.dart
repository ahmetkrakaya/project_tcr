import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/user_model.dart';

/// Auth Remote DataSource Interface
abstract class AuthRemoteDataSource {
  Future<UserModel> signInWithEmail(String email, String password);
  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  });

  Future<UserModel> verifyEmail(String email, String token);

  Future<void> resendVerificationEmail(String email);
  Future<void> signOut();
  Future<UserModel?> getCurrentUser();
  Future<UserModel> updateProfile(Map<String, dynamic> data);
  Future<List<String>> getUserRoles(String userId);
  Future<IceCardModel?> getIceCard(String userId);
  Future<IceCardModel> upsertIceCard(Map<String, dynamic> data);
  Future<void> resetPassword(String email, {String? redirectTo});
  Future<void> updatePassword(String newPassword);
  Stream<AuthState> get authStateChanges;
  
  /// Email'in zaten kayıtlı olup olmadığını kontrol et
  Future<bool> checkEmailExists(String email);
}

/// Auth Remote DataSource Implementation
class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  final SupabaseClient _supabase;

  AuthRemoteDataSourceImpl({
    required SupabaseClient supabase,
  })  : _supabase = supabase;

  @override
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  @override
  Future<UserModel> signInWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw const AppAuthException(
          message: 'Email veya şifre hatalı',
          code: 'INVALID_CREDENTIALS',
        );
      }

      // Email doğrulanmamışsa hata ver
      if (response.user!.emailConfirmedAt == null) {
        throw const AppAuthException(
          message: 'Lütfen email adresinizi doğrulayın',
          code: 'EMAIL_NOT_CONFIRMED',
        );
      }

      // Kullanıcı profilini al
      final userProfile = await _fetchUserProfile(response.user!.id);

      // Kullanıcı aktif değilse oturumu kapat ve hata ver
      if (!userProfile.isActive) {
        // Önce oturumu kapat ki router home'a yönlendirmesin
        await _supabase.auth.signOut();
        throw const AppAuthException(
          message: 'Hesabınız henüz onaylanmadı. Lütfen yetkili bir kişi tarafından onaylanmanızı bekleyin.',
          code: 'USER_NOT_APPROVED',
        );
      }

      return userProfile;
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppAuthException(
        message: 'Giriş başarısız: ${e.toString()}',
        code: 'SIGN_IN_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel?> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      // Email doğrulama gerektiren kayıt
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
        },
        emailRedirectTo: null, // Email doğrulama sonrası yönlendirme yok
      );

      if (response.user == null) {
        throw const AppAuthException(
          message: 'Kayıt başarısız',
          code: 'SIGN_UP_FAILED',
        );
      }

      // Email doğrulanmamışsa null döndür (email doğrulama bekleniyor)
      // NOT: Supabase'de email confirmation ayarları açık olmalı
      // Eğer email confirmation kapalıysa, bu kontrol her zaman false döner
      if (response.user!.emailConfirmedAt == null) {
        // Email doğrulama bekleniyor - null döndür
        return null;
      }

      // Email doğrulanmışsa profil oluşturulmuş olmalı (trigger tarafından)
      // Profil yoksa oluştur
      try {
        return await _fetchUserProfile(response.user!.id);
      } catch (e) {
        // Profil henüz oluşturulmamışsa bekle
        // Email doğrulama trigger'ı profil oluşturacak
        return null;
      }
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppAuthException(
        message: 'Kayıt başarısız: ${e.toString()}',
        code: 'SIGN_UP_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel> verifyEmail(String email, String token) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );

      if (response.user == null) {
        throw const AppAuthException(
          message: 'Email doğrulama başarısız',
          code: 'EMAIL_VERIFICATION_FAILED',
        );
      }

      // Email doğrulandıktan sonra profil oluşturulmuş olmalı (trigger tarafından)
      // Biraz bekle ve profil oluşturuldu mu kontrol et
      await Future.delayed(const Duration(seconds: 1));
      
      return await _fetchUserProfile(response.user!.id);
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      if (e is AppAuthException) rethrow;
      throw AppAuthException(
        message: 'Email doğrulama başarısız: ${e.toString()}',
        code: 'EMAIL_VERIFICATION_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<void> resendVerificationEmail(String email) async {
    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
      );
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      throw AppAuthException(
        message: 'Doğrulama emaili gönderilemedi: ${e.toString()}',
        code: 'RESEND_EMAIL_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<void> resetPassword(String email, {String? redirectTo}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      );
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      throw AppAuthException(
        message: 'Şifre sıfırlama başarısız: ${e.toString()}',
        code: 'RESET_PASSWORD_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AppAuthException(
        message: _parseAuthError(e.message),
        code: e.statusCode ?? 'AUTH_ERROR',
        originalException: e,
      );
    } catch (e) {
      throw AppAuthException(
        message: 'Şifre güncellenemedi: ${e.toString()}',
        code: 'UPDATE_PASSWORD_ERROR',
        originalException: e,
      );
    }
  }

  String _parseAuthError(String message) {
    if (message.contains('Invalid login credentials')) {
      return 'Email veya şifre hatalı';
    }
    if (message.contains('Email not confirmed')) {
      return 'Lütfen email adresinizi doğrulayın';
    }
    if (message.contains('User already registered')) {
      return 'Bu email adresi zaten kayıtlı';
    }
    if (message.contains('Password should be at least')) {
      return 'Şifre en az 6 karakter olmalıdır';
    }
    if (message.contains('Unable to validate email')) {
      return 'Geçersiz email adresi';
    }
    return message;
  }

  @override
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      throw AppAuthException(
        message: 'Çıkış başarısız: ${e.toString()}',
        code: 'SIGN_OUT_ERROR',
        originalException: e,
      );
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return null;
      
      // Email doğrulanmamışsa null döndür
      if (user.emailConfirmedAt == null) {
        return null;
      }
      
      final userProfile = await _fetchUserProfile(user.id);
      
      // Kullanıcı aktif değilse null döndür (giriş yapamaz)
      if (!userProfile.isActive) {
        return null;
      }
      
      return userProfile;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<UserModel> updateProfile(Map<String, dynamic> data) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      if (userId == null) {
        throw const AppAuthException(
          message: 'Kullanıcı oturumu bulunamadı',
          code: 'NO_SESSION',
        );
      }

      await _supabase
          .from('users')
          .update(data)
          .eq('id', userId);

      return await _fetchUserProfile(userId);
    } catch (e) {
      throw ServerException(
        message: 'Profil güncellenemedi: ${e.toString()}',
        originalException: e,
      );
    }
  }

  @override
  Future<List<String>> getUserRoles(String userId) async {
    try {
      final response = await _supabase
          .from('user_roles')
          .select('role')
          .eq('user_id', userId);

      return (response as List)
          .map((r) => r['role'] as String)
          .toList();
    } catch (e) {
      return ['member'];
    }
  }

  @override
  Future<IceCardModel?> getIceCard(String userId) async {
    try {
      final response = await _supabase
          .from('ice_cards')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      if (response == null) return null;
      return IceCardModel.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<IceCardModel> upsertIceCard(Map<String, dynamic> data) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      
      if (userId == null) {
        throw const AppAuthException(
          message: 'Kullanıcı oturumu bulunamadı',
          code: 'NO_SESSION',
        );
      }

      final existingCard = await getIceCard(userId);
      
      Map<String, dynamic> response;
      if (existingCard != null) {
        response = await _supabase
            .from('ice_cards')
            .update(data)
            .eq('user_id', userId)
            .select()
            .single();
      } else {
        response = await _supabase
            .from('ice_cards')
            .insert({...data, 'user_id': userId})
            .select()
            .single();
      }

      return IceCardModel.fromJson(response);
    } catch (e) {
      throw ServerException(
        message: 'ICE kartı kaydedilemedi: ${e.toString()}',
        originalException: e,
      );
    }
  }

  Future<UserModel> _fetchUserProfile(String userId) async {
    final response = await _supabase
        .from('users')
        .select()
        .eq('id', userId)
        .single();

    return UserModel.fromJson(response);
  }

  @override
  Future<bool> checkEmailExists(String email) async {
    try {
      // users tablosunda email kontrolü yap
      final response = await _supabase
          .from('users')
          .select('id')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();

      return response != null;
    } catch (e) {
      // Hata durumunda false döndür (email kontrolü yapılamadı)
      return false;
    }
  }
}
