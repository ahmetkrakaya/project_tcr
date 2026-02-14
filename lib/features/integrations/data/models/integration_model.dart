import '../../domain/entities/integration_entity.dart';

/// Integration Model
class IntegrationModel {
  final String id;
  final String userId;
  final String provider;
  final String? providerUserId;
  final String accessToken;
  final String? refreshToken;
  final DateTime? tokenExpiresAt;
  final List<String>? scopes;
  final Map<String, dynamic>? athleteData;
  final DateTime connectedAt;
  final DateTime? lastSyncAt;
  final bool syncEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const IntegrationModel({
    required this.id,
    required this.userId,
    required this.provider,
    this.providerUserId,
    required this.accessToken,
    this.refreshToken,
    this.tokenExpiresAt,
    this.scopes,
    this.athleteData,
    required this.connectedAt,
    this.lastSyncAt,
    this.syncEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory IntegrationModel.fromJson(Map<String, dynamic> json) {
    return IntegrationModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      provider: json['provider'] as String,
      providerUserId: json['provider_user_id'] as String?,
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      tokenExpiresAt: json['token_expires_at'] != null
          ? DateTime.parse(json['token_expires_at'] as String)
          : null,
      scopes: json['scopes'] != null
          ? List<String>.from(json['scopes'] as List)
          : null,
      athleteData: json['athlete_data'] as Map<String, dynamic>?,
      connectedAt: DateTime.parse(json['connected_at'] as String),
      lastSyncAt: json['last_sync_at'] != null
          ? DateTime.parse(json['last_sync_at'] as String)
          : null,
      syncEnabled: json['sync_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'provider': provider,
      'provider_user_id': providerUserId,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_expires_at': tokenExpiresAt?.toIso8601String(),
      'scopes': scopes,
      'athlete_data': athleteData,
      'connected_at': connectedAt.toIso8601String(),
      'last_sync_at': lastSyncAt?.toIso8601String(),
      'sync_enabled': syncEnabled,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'user_id': userId,
      'provider': provider,
      'provider_user_id': providerUserId,
      'access_token': accessToken,
      'refresh_token': refreshToken,
      'token_expires_at': tokenExpiresAt?.toIso8601String(),
      'scopes': scopes,
      'athlete_data': athleteData,
      'sync_enabled': syncEnabled,
    };
  }

  IntegrationEntity toEntity() {
    String? athleteName;
    String? athleteAvatarUrl;
    
    if (athleteData != null) {
      final firstName = athleteData!['firstname'] as String?;
      final lastName = athleteData!['lastname'] as String?;
      athleteName = [firstName, lastName]
          .where((s) => s != null && s.isNotEmpty)
          .join(' ');
      athleteAvatarUrl = athleteData!['profile'] as String? ??
          athleteData!['profile_medium'] as String?;
    }

    return IntegrationEntity(
      id: id,
      userId: userId,
      provider: IntegrationProvider.fromString(provider),
      providerUserId: providerUserId,
      athleteName: athleteName,
      athleteAvatarUrl: athleteAvatarUrl,
      connectedAt: connectedAt,
      lastSyncAt: lastSyncAt,
      syncEnabled: syncEnabled,
    );
  }

  IntegrationModel copyWith({
    String? id,
    String? userId,
    String? provider,
    String? providerUserId,
    String? accessToken,
    String? refreshToken,
    DateTime? tokenExpiresAt,
    List<String>? scopes,
    Map<String, dynamic>? athleteData,
    DateTime? connectedAt,
    DateTime? lastSyncAt,
    bool? syncEnabled,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IntegrationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      provider: provider ?? this.provider,
      providerUserId: providerUserId ?? this.providerUserId,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenExpiresAt: tokenExpiresAt ?? this.tokenExpiresAt,
      scopes: scopes ?? this.scopes,
      athleteData: athleteData ?? this.athleteData,
      connectedAt: connectedAt ?? this.connectedAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
