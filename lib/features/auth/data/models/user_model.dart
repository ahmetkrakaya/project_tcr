import '../../domain/entities/user_entity.dart';

/// User Model - Data layer representation
class UserModel {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? bloodType;
  final String? tshirtSize;
  final String? shoeSize;
  final String? avatarUrl;
  final String? bio;
  final String? gender;
  final String? birthDate;
  final double? weight;
  final double? vdot;
  final String? vdotUpdatedAt;
  final bool isActive;
  final String? createdAt;
  final String? updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.bloodType,
    this.tshirtSize,
    this.shoeSize,
    this.avatarUrl,
    this.bio,
    this.gender,
    this.birthDate,
    this.weight,
    this.vdot,
    this.vdotUpdatedAt,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
      phone: json['phone'] as String?,
      bloodType: json['blood_type'] as String?,
      tshirtSize: json['tshirt_size'] as String?,
      shoeSize: json['shoe_size'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      bio: json['bio'] as String?,
      gender: json['gender'] as String?,
      birthDate: json['birth_date'] as String?,
      weight: (json['weight_kg'] as num?)?.toDouble(),
      vdot: (json['vdot'] as num?)?.toDouble(),
      vdotUpdatedAt: json['vdot_updated_at'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'first_name': firstName,
      'last_name': lastName,
      'phone': phone,
      'blood_type': bloodType,
      'tshirt_size': tshirtSize,
      'shoe_size': shoeSize,
      'avatar_url': avatarUrl,
      'bio': bio,
      'gender': gender,
      'birth_date': birthDate,
      'weight_kg': weight,
      'vdot': vdot,
      'vdot_updated_at': vdotUpdatedAt,
      'is_active': isActive,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Convert to Entity
  UserEntity toEntity({List<String>? roles}) {
    return UserEntity(
      id: id,
      email: email,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      bloodType: _parseBloodType(bloodType),
      tshirtSize: _parseTShirtSize(tshirtSize),
      shoeSize: shoeSize,
      avatarUrl: avatarUrl,
      bio: bio,
      gender: _parseGender(gender),
      birthDate: birthDate != null ? DateTime.tryParse(birthDate!) : null,
      weight: weight,
      vdot: vdot,
      vdotUpdatedAt: vdotUpdatedAt != null ? DateTime.parse(vdotUpdatedAt!) : null,
      isActive: isActive,
      roles: roles?.map(_parseRole).toList() ?? [UserRole.member],
      createdAt: createdAt != null ? DateTime.parse(createdAt!) : null,
      updatedAt: updatedAt != null ? DateTime.parse(updatedAt!) : null,
    );
  }

  /// Create from Entity
  static UserModel fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      email: entity.email,
      firstName: entity.firstName,
      lastName: entity.lastName,
      phone: entity.phone,
      bloodType: _bloodTypeToString(entity.bloodType),
      tshirtSize: _tshirtSizeToString(entity.tshirtSize),
      shoeSize: entity.shoeSize,
      avatarUrl: entity.avatarUrl,
      bio: entity.bio,
      gender: _genderToString(entity.gender),
      birthDate: entity.birthDate?.toIso8601String(),
      weight: entity.weight,
      vdot: entity.vdot,
      vdotUpdatedAt: entity.vdotUpdatedAt?.toIso8601String(),
      isActive: entity.isActive,
    );
  }

  static BloodType _parseBloodType(String? value) {
    switch (value) {
      case 'A+':
        return BloodType.aPositive;
      case 'A-':
        return BloodType.aNegative;
      case 'B+':
        return BloodType.bPositive;
      case 'B-':
        return BloodType.bNegative;
      case 'AB+':
        return BloodType.abPositive;
      case 'AB-':
        return BloodType.abNegative;
      case 'O+':
        return BloodType.oPositive;
      case 'O-':
        return BloodType.oNegative;
      default:
        return BloodType.unknown;
    }
  }

  static Gender? _parseGender(String? value) {
    switch (value) {
      case 'male':
        return Gender.male;
      case 'female':
        return Gender.female;
      case 'unknown':
        return Gender.unknown;
      default:
        return null;
    }
  }

  static String _bloodTypeToString(BloodType type) {
    switch (type) {
      case BloodType.aPositive:
        return 'A+';
      case BloodType.aNegative:
        return 'A-';
      case BloodType.bPositive:
        return 'B+';
      case BloodType.bNegative:
        return 'B-';
      case BloodType.abPositive:
        return 'AB+';
      case BloodType.abNegative:
        return 'AB-';
      case BloodType.oPositive:
        return 'O+';
      case BloodType.oNegative:
        return 'O-';
      case BloodType.unknown:
        return 'unknown';
    }
  }

  static String? _genderToString(Gender? gender) {
    switch (gender) {
      case Gender.male:
        return 'male';
      case Gender.female:
        return 'female';
      case Gender.unknown:
        return 'unknown';
      case null:
        return null;
    }
  }

  static TShirtSize? _parseTShirtSize(String? value) {
    switch (value?.toUpperCase()) {
      case 'XS':
        return TShirtSize.xs;
      case 'S':
        return TShirtSize.s;
      case 'M':
        return TShirtSize.m;
      case 'L':
        return TShirtSize.l;
      case 'XL':
        return TShirtSize.xl;
      case 'XXL':
        return TShirtSize.xxl;
      case 'XXXL':
        return TShirtSize.xxxl;
      default:
        return null;
    }
  }

  static String? _tshirtSizeToString(TShirtSize? size) {
    return size?.name.toUpperCase();
  }

  static UserRole _parseRole(String role) {
    switch (role) {
      case 'super_admin':
        return UserRole.superAdmin;
      case 'coach':
        return UserRole.coach;
      default:
        return UserRole.member;
    }
  }
}

/// User Role Model
class UserRoleModel {
  final String id;
  final String userId;
  final String role;
  final String? assignedBy;
  final String? assignedAt;

  const UserRoleModel({
    required this.id,
    required this.userId,
    required this.role,
    this.assignedBy,
    this.assignedAt,
  });

  factory UserRoleModel.fromJson(Map<String, dynamic> json) {
    return UserRoleModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      role: json['role'] as String,
      assignedBy: json['assigned_by'] as String?,
      assignedAt: json['assigned_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'role': role,
      'assigned_by': assignedBy,
      'assigned_at': assignedAt,
    };
  }
}

/// ICE Card Model
class IceCardModel {
  final String id;
  final String userId;
  final String? chronicDiseases;
  final String? medications;
  final String? allergies;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;
  final String? additionalNotes;
  final String? createdAt;
  final String? updatedAt;

  const IceCardModel({
    required this.id,
    required this.userId,
    this.chronicDiseases,
    this.medications,
    this.allergies,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.emergencyContactRelation,
    this.additionalNotes,
    this.createdAt,
    this.updatedAt,
  });

  factory IceCardModel.fromJson(Map<String, dynamic> json) {
    return IceCardModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      chronicDiseases: json['chronic_diseases'] as String?,
      medications: json['medications'] as String?,
      allergies: json['allergies'] as String?,
      emergencyContactName: json['emergency_contact_name'] as String?,
      emergencyContactPhone: json['emergency_contact_phone'] as String?,
      emergencyContactRelation: json['emergency_contact_relation'] as String?,
      additionalNotes: json['additional_notes'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'chronic_diseases': chronicDiseases,
      'medications': medications,
      'allergies': allergies,
      'emergency_contact_name': emergencyContactName,
      'emergency_contact_phone': emergencyContactPhone,
      'emergency_contact_relation': emergencyContactRelation,
      'additional_notes': additionalNotes,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// Convert to Entity
  IceCardEntity toEntity() {
    return IceCardEntity(
      id: id,
      userId: userId,
      chronicDiseases: chronicDiseases,
      medications: medications,
      allergies: allergies,
      emergencyContactName: emergencyContactName,
      emergencyContactPhone: emergencyContactPhone,
      emergencyContactRelation: emergencyContactRelation,
      additionalNotes: additionalNotes,
      createdAt: createdAt != null ? DateTime.parse(createdAt!) : null,
      updatedAt: updatedAt != null ? DateTime.parse(updatedAt!) : null,
    );
  }
}
