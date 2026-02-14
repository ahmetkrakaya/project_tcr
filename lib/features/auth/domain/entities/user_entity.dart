/// User Role Enum
enum UserRole { superAdmin, coach, member }

/// Blood Type Enum
enum BloodType { aPositive, aNegative, bPositive, bNegative, abPositive, abNegative, oPositive, oNegative, unknown }

/// T-Shirt Size Enum
enum TShirtSize { xs, s, m, l, xl, xxl, xxxl }

/// Gender Enum
enum Gender { male, female, unknown }

/// User Entity
class UserEntity {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final BloodType bloodType;
  final TShirtSize? tshirtSize;
  final String? shoeSize;
  final String? avatarUrl;
  final String? bio;
  final Gender? gender;
  final DateTime? birthDate;
  final double? weight;
  final double? vdot;
  final DateTime? vdotUpdatedAt;
  final bool isActive;
  final List<UserRole> roles;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const UserEntity({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phone,
    this.bloodType = BloodType.unknown,
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
    this.roles = const [UserRole.member],
    this.createdAt,
    this.updatedAt,
  });

  /// Full name
  String get fullName {
    if (firstName == null && lastName == null) return email;
    return '${firstName ?? ''} ${lastName ?? ''}'.trim();
  }

  /// Check if user is admin
  bool get isAdmin => roles.contains(UserRole.superAdmin);

  /// Check if user is coach
  bool get isCoach => roles.contains(UserRole.coach);

  /// Check if user is admin or coach
  bool get isAdminOrCoach => isAdmin || isCoach;

  /// Initials for avatar
  String get initials {
    if (firstName != null && lastName != null) {
      return '${firstName![0]}${lastName![0]}'.toUpperCase();
    }
    if (firstName != null) {
      return firstName!.substring(0, firstName!.length >= 2 ? 2 : 1).toUpperCase();
    }
    return email.substring(0, 2).toUpperCase();
  }

  /// VDOT değeri var mı?
  bool get hasVdot => vdot != null && vdot! > 0;

  UserEntity copyWith({
    String? id,
    String? email,
    String? firstName,
    String? lastName,
    String? phone,
    BloodType? bloodType,
    TShirtSize? tshirtSize,
    String? shoeSize,
    String? avatarUrl,
    String? bio,
    Gender? gender,
    DateTime? birthDate,
    double? weight,
    double? vdot,
    DateTime? vdotUpdatedAt,
    bool? isActive,
    List<UserRole>? roles,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phone: phone ?? this.phone,
      bloodType: bloodType ?? this.bloodType,
      tshirtSize: tshirtSize ?? this.tshirtSize,
      shoeSize: shoeSize ?? this.shoeSize,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      weight: weight ?? this.weight,
      vdot: vdot ?? this.vdot,
      vdotUpdatedAt: vdotUpdatedAt ?? this.vdotUpdatedAt,
      isActive: isActive ?? this.isActive,
      roles: roles ?? this.roles,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

/// ICE Card Entity (In Case of Emergency)
class IceCardEntity {
  final String id;
  final String userId;
  final String? chronicDiseases;
  final String? medications;
  final String? allergies;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? emergencyContactRelation;
  final String? additionalNotes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const IceCardEntity({
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

  /// Check if ICE card has any emergency info
  bool get hasEmergencyInfo {
    return chronicDiseases != null ||
        medications != null ||
        allergies != null ||
        emergencyContactName != null;
  }

  IceCardEntity copyWith({
    String? id,
    String? userId,
    String? chronicDiseases,
    String? medications,
    String? allergies,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? emergencyContactRelation,
    String? additionalNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return IceCardEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      chronicDiseases: chronicDiseases ?? this.chronicDiseases,
      medications: medications ?? this.medications,
      allergies: allergies ?? this.allergies,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone: emergencyContactPhone ?? this.emergencyContactPhone,
      emergencyContactRelation: emergencyContactRelation ?? this.emergencyContactRelation,
      additionalNotes: additionalNotes ?? this.additionalNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
