import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../../core/constants/app_constants.dart';
import '../../../../shared/providers/auth_provider.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

/// Auth Repository Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final supabase = ref.watch(supabaseClientProvider);
  final remoteDataSource = AuthRemoteDataSourceImpl(supabase: supabase);
  return AuthRepositoryImpl(remoteDataSource: remoteDataSource);
});

/// Auth State
sealed class AuthState {
  const AuthState();
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

class AuthAuthenticated extends AuthState {
  final UserEntity user;
  const AuthAuthenticated(this.user);
}

class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

class AuthError extends AuthState {
  final String message;
  const AuthError(this.message);
}

class AuthEmailVerificationSent extends AuthState {
  final String email;
  const AuthEmailVerificationSent(this.email);
}

class AuthPendingApproval extends AuthState {
  final String email;
  const AuthPendingApproval(this.email);
}

/// Şifre sıfırlama linkine tıklandıktan sonra yeni şifre belirleme bekleniyor
class AuthNeedsPasswordReset extends AuthState {
  final UserEntity user;
  const AuthNeedsPasswordReset(this.user);
}

/// Auth Result - işlem sonuçları için wrapper class
class AuthResult {
  final UserEntity? user;
  final String? error;
  final bool emailVerificationRequired;
  final String? email;

  const AuthResult._({
    this.user,
    this.error,
    this.emailVerificationRequired = false,
    this.email,
  });

  factory AuthResult.success(UserEntity user) => AuthResult._(user: user);
  factory AuthResult.failure(String error) => AuthResult._(error: error);
  factory AuthResult.emailVerification(String email) => AuthResult._(
    emailVerificationRequired: true,
    email: email,
  );

  bool get isSuccess => user != null && error == null;
  bool get isFailure => error != null;
}

/// Auth Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repository) : super(const AuthInitial()) {
    _init();
    _authSubscription = _repository.authStateChanges.listen((data) {
      if (data.event == supabase.AuthChangeEvent.passwordRecovery) {
        _repository.getCurrentUser().then((result) {
          if (result.user != null) {
            state = AuthNeedsPasswordReset(result.user!);
          }
        });
      }
    });
  }

  final AuthRepository _repository;
  StreamSubscription<supabase.AuthState>? _authSubscription;

  Future<void> _init() async {
    state = const AuthLoading();
    final result = await _repository.getCurrentUser();
    
    if (result.user != null) {
      state = AuthAuthenticated(result.user!);
    } else {
      state = const AuthUnauthenticated();
    }
  }

  /// Şifre sıfırlama tamamlandıktan sonra state'i güncelle
  void completePasswordReset() {
    if (state is AuthNeedsPasswordReset) {
      state = AuthAuthenticated((state as AuthNeedsPasswordReset).user);
    }
  }

  /// Dispose subscription (provider'da ref.onDispose ile çağrılabilir)
  void disposeNotifier() {
    _authSubscription?.cancel();
  }

  /// Email/şifre ile giriş - AuthResult döndürür, UI hata yönetimini kendisi yapar
  Future<AuthResult> signInWithEmail(String email, String password) async {
    state = const AuthLoading();
    
    final result = await _repository.signInWithEmail(email, password);
    
    if (result.failure != null) {
      // Hata durumunda state'i unauthenticated yap, hata UI'da gösterilecek
      state = const AuthUnauthenticated();
      return AuthResult.failure(result.failure!.message);
    } else if (result.user != null) {
      state = AuthAuthenticated(result.user!);
      return AuthResult.success(result.user!);
    }
    
    // Beklenmeyen durum
    state = const AuthUnauthenticated();
    return AuthResult.failure('Beklenmeyen bir hata oluştu');
  }

  /// Email/şifre ile kayıt - AuthResult döndürür, UI hata yönetimini kendisi yapar
  Future<AuthResult> signUpWithEmail({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    state = const AuthLoading();
    
    final result = await _repository.signUpWithEmail(
      email: email,
      password: password,
      firstName: firstName,
      lastName: lastName,
    );
    
    if (result.failure != null) {
      // Hata durumunda state'i unauthenticated yap, hata UI'da gösterilecek
      state = const AuthUnauthenticated();
      return AuthResult.failure(result.failure!.message);
    } else if (result.user == null) {
      // Email doğrulama bekleniyor
      // NOT: Supabase'de email confirmation ayarları açık olmalı
      // Authentication > Settings > Enable email confirmations
      state = AuthEmailVerificationSent(email);
      return AuthResult.emailVerification(email);
    } else {
      // Email doğrulama kapalıysa veya zaten doğrulanmışsa direkt authenticated
      state = AuthAuthenticated(result.user!);
      return AuthResult.success(result.user!);
    }
  }

  /// Email doğrulama - AuthResult döndürür
  Future<AuthResult> verifyEmail(String email, String token) async {
    state = const AuthLoading();
    
    final result = await _repository.verifyEmail(email, token);
    
    if (result.failure != null) {
      // Hata durumunda state'i unauthenticated yap
      state = const AuthUnauthenticated();
      return AuthResult.failure(result.failure!.message);
    } else if (result.user != null) {
      // Email doğrulandı, kullanıcının aktif olup olmadığını kontrol et
      if (!result.user!.isActive) {
        // Kullanıcı henüz onaylanmamış, onay bekliyor
        // ÖNEMLİ: Oturumu mutlaka kapat çünkü giriş yapamaz
        // Önce state'i unauthenticated yap ki router home'a yönlendirmesin
        state = const AuthUnauthenticated();
        // Session'ı kapatmak için signOut çağır
        await _repository.signOut();
        // Biraz bekle ki session gerçekten kapansın
        await Future.delayed(const Duration(milliseconds: 300));
        // Sonra pending approval state'ine geç
        state = AuthPendingApproval(email);
        return AuthResult.failure('Hesabınız henüz onaylanmamış');
      } else {
        // Kullanıcı aktif, giriş yapabilir
        state = AuthAuthenticated(result.user!);
        return AuthResult.success(result.user!);
      }
    }
    
    // Beklenmeyen durum
    state = const AuthUnauthenticated();
    return AuthResult.failure('Doğrulama başarısız');
  }

  Future<bool> resendVerificationEmail(String email) async {
    final failure = await _repository.resendVerificationEmail(email);
    return failure == null;
  }

  Future<bool> resetPassword(String email) async {
    final failure = await _repository.resetPassword(
      email,
      redirectTo: AppConstants.authResetPasswordRedirectUrl,
    );
    return failure == null;
  }

  /// Yeni şifre belirle (şifre sıfırlama linkinden sonra bu sayfada çağrılır)
  Future<String?> updatePassword(String newPassword) async {
    final failure = await _repository.updatePassword(newPassword);
    return failure?.message;
  }

  Future<void> signOut() async {
    state = const AuthLoading();
    
    final failure = await _repository.signOut();
    
    if (failure != null) {
      state = AuthError(failure.message);
    }
    
    state = const AuthUnauthenticated();
  }

  Future<void> updateProfile({
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
    final currentUser = state is AuthAuthenticated
        ? (state as AuthAuthenticated).user
        : null;
    
    if (currentUser == null) return;
    
    final result = await _repository.updateProfile(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      bloodType: bloodType,
      tshirtSize: tshirtSize,
      shoeSize: shoeSize,
      bio: bio,
      gender: gender,
      birthDate: birthDate,
      weight: weight,
    );
    
    if (result.user != null) {
      state = AuthAuthenticated(result.user!);
    }
  }

  Future<void> refreshUser() async {
    final result = await _repository.getCurrentUser();
    
    if (result.user != null) {
      // Kullanıcı aktif mi kontrol et
      if (result.user!.isActive) {
        state = AuthAuthenticated(result.user!);
      } else {
        // Kullanıcı aktif değilse oturumu kapat
        await _repository.signOut();
        state = const AuthUnauthenticated();
      }
    } else {
      state = const AuthUnauthenticated();
    }
  }

  /// Email'in zaten kayıtlı olup olmadığını kontrol et
  Future<bool> checkEmailExists(String email) async {
    return await _repository.checkEmailExists(email);
  }
}

/// Auth Notifier Provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final repository = ref.watch(authRepositoryProvider);
  final notifier = AuthNotifier(repository);
  ref.onDispose(() => notifier.disposeNotifier());
  return notifier;
});

/// Current User Profile Provider
final currentUserProfileProvider = Provider<UserEntity?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  if (authState is AuthAuthenticated) {
    return authState.user;
  }
  if (authState is AuthNeedsPasswordReset) {
    return authState.user;
  }
  return null;
});

/// User Roles Provider
final userRolesProvider = Provider<List<UserRole>>((ref) {
  final user = ref.watch(currentUserProfileProvider);
  return user?.roles ?? [UserRole.member];
});

/// Is Admin Provider
final isAdminProvider = Provider<bool>((ref) {
  final roles = ref.watch(userRolesProvider);
  return roles.contains(UserRole.superAdmin);
});

/// Is Coach Provider
final isCoachProvider = Provider<bool>((ref) {
  final roles = ref.watch(userRolesProvider);
  return roles.contains(UserRole.coach);
});

/// Is Admin or Coach Provider
final isAdminOrCoachProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(isAdminProvider);
  final isCoach = ref.watch(isCoachProvider);
  return isAdmin || isCoach;
});

/// User VDOT Provider
final userVdotProvider = Provider<double?>((ref) {
  final user = ref.watch(currentUserProfileProvider);
  return user?.vdot;
});

/// VDOT Update Notifier
class VdotUpdateNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;

  VdotUpdateNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<bool> updateVdot(double vdot) async {
    state = const AsyncValue.loading();
    try {
      final supabase = _ref.read(supabaseClientProvider);
      final userId = supabase.auth.currentUser?.id;
      
      if (userId == null) {
        state = AsyncValue.error('Kullanıcı bulunamadı', StackTrace.current);
        return false;
      }

      await supabase.from('users').update({
        'vdot': vdot,
        'vdot_updated_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);

      // Auth state'i yenile
      await _ref.read(authNotifierProvider.notifier).refreshUser();
      
      state = const AsyncValue.data(null);
      return true;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }
}

/// VDOT Update Provider
final vdotUpdateProvider = StateNotifierProvider<VdotUpdateNotifier, AsyncValue<void>>((ref) {
  return VdotUpdateNotifier(ref);
});

/// ICE Card Provider
final iceCardProvider = FutureProvider.family<IceCardEntity?, String>((ref, userId) async {
  final repository = ref.watch(authRepositoryProvider);
  final result = await repository.getIceCard(userId);
  return result.iceCard;
});

/// ICE Card Notifier for updates
class IceCardNotifier extends StateNotifier<AsyncValue<IceCardEntity?>> {
  final AuthRepository _repository;
  final String _userId;

  IceCardNotifier(this._repository, this._userId) : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    final result = await _repository.getIceCard(_userId);
    state = AsyncValue.data(result.iceCard);
  }

  Future<void> update({
    String? chronicDiseases,
    String? medications,
    String? allergies,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? additionalNotes,
  }) async {
    state = const AsyncValue.loading();
    
    final result = await _repository.updateIceCard(
      chronicDiseases: chronicDiseases,
      medications: medications,
      allergies: allergies,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      emergencyContactRelation: emergencyContactRelation,
      additionalNotes: additionalNotes,
    );
    
    if (result.failure != null) {
      state = AsyncValue.error(result.failure!.message, StackTrace.current);
    } else {
      state = AsyncValue.data(result.iceCard);
    }
  }
}

final iceCardNotifierProvider = StateNotifierProvider.family<IceCardNotifier, AsyncValue<IceCardEntity?>, String>(
  (ref, userId) {
    final repository = ref.watch(authRepositoryProvider);
    return IceCardNotifier(repository, userId);
  },
);

/// User Profile Provider (by userId)
final userProfileProvider = FutureProvider.family<UserEntity?, String>((ref, userId) async {
  final supabase = ref.watch(supabaseClientProvider);
  
  try {
    // Supabase'den kullanıcı profilini al
    final response = await supabase
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    
    if (response == null) return null;
    
    // UserModel'e çevir
    final userModel = UserModel.fromJson(response);
    
    // Rolleri al (repository'de getUserRoles yoksa direkt datasource'dan al)
    final remoteDataSource = AuthRemoteDataSourceImpl(supabase: supabase);
    final roles = await remoteDataSource.getUserRoles(userId);
    
    return userModel.toEntity(roles: roles);
  } catch (e) {
    return null;
  }
});
