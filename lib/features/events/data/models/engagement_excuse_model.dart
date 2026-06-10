class EngagementExcuseType {
  EngagementExcuseType._();

  static const inactiveApp = 'inactive_app';
  static const inactiveEvent = 'inactive_event';

  static String label(String type) {
    switch (type) {
      case inactiveApp:
        return 'Uygulamaya girmeme';
      case inactiveEvent:
        return 'Etkinliğe katılmama';
      default:
        return type;
    }
  }
}

class PendingEngagementExcuseModel {
  final String id;
  final String excuseType;
  final String status;
  final DateTime? sentAt;

  const PendingEngagementExcuseModel({
    required this.id,
    required this.excuseType,
    required this.status,
    this.sentAt,
  });

  factory PendingEngagementExcuseModel.fromJson(Map<String, dynamic> json) {
    return PendingEngagementExcuseModel(
      id: json['id'] as String,
      excuseType: json['excuse_type'] as String,
      status: json['status'] as String,
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
    );
  }

  String get title {
    switch (excuseType) {
      case EngagementExcuseType.inactiveApp:
        return 'Uygulama Kullanımı Hakkında';
      case EngagementExcuseType.inactiveEvent:
        return 'Etkinlik Katılımı Hakkında';
      default:
        return 'Mazaret Bildirimi';
    }
  }

  String get description {
    switch (excuseType) {
      case EngagementExcuseType.inactiveApp:
        return 'Son 30 gündür uygulamaya giriş yapmadığınız tespit edildi. '
            'Kulüp ile iletişimde kalabilmek için lütfen mazaretinizi aşağıya yazın. '
            'En az 30 karakter girmeniz gerekmektedir.';
      case EngagementExcuseType.inactiveEvent:
        return 'Son 30 gündür hiçbir etkinliğe katılmadığınız tespit edildi. '
            'Kulüp aktivitelerine katılımınız önemlidir. Lütfen mazaretinizi aşağıya yazın. '
            'En az 30 karakter girmeniz gerekmektedir.';
      default:
        return 'Lütfen mazaretinizi en az 30 karakter olacak şekilde yazın.';
    }
  }
}

class EngagementExcuseItemModel {
  final String requestId;
  final String userId;
  final String fullName;
  final String excuseType;
  final String status;
  final String? excuseText;
  final DateTime? sentAt;
  final DateTime? submittedAt;
  final DateTime? exemptUntil;
  final DateTime? reviewedAt;

  const EngagementExcuseItemModel({
    required this.requestId,
    required this.userId,
    required this.fullName,
    required this.excuseType,
    required this.status,
    this.excuseText,
    this.sentAt,
    this.submittedAt,
    this.exemptUntil,
    this.reviewedAt,
  });

  factory EngagementExcuseItemModel.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String? key) {
      final value = json[key];
      if (value == null) return null;
      return DateTime.parse(value as String);
    }

    return EngagementExcuseItemModel(
      requestId: json['request_id'] as String,
      userId: json['user_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      excuseType: json['excuse_type'] as String,
      status: json['status'] as String,
      excuseText: json['excuse_text'] as String?,
      sentAt: parseDate('sent_at'),
      submittedAt: parseDate('submitted_at'),
      exemptUntil: parseDate('exempt_until'),
      reviewedAt: parseDate('reviewed_at'),
    );
  }
}

class EngagementExcuseAdminReportsModel {
  final List<EngagementExcuseItemModel> awaitingSubmission;
  final List<EngagementExcuseItemModel> submitted;
  final List<EngagementExcuseItemModel> accepted;

  const EngagementExcuseAdminReportsModel({
    required this.awaitingSubmission,
    required this.submitted,
    required this.accepted,
  });

  factory EngagementExcuseAdminReportsModel.fromJson(
    Map<String, dynamic> json,
  ) {
    List<EngagementExcuseItemModel> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return [];
      return raw
          .map(
            (e) => EngagementExcuseItemModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
    }

    return EngagementExcuseAdminReportsModel(
      awaitingSubmission: parseList('awaiting_submission'),
      submitted: parseList('submitted'),
      accepted: parseList('accepted'),
    );
  }
}

class SendEngagementExcuseResultModel {
  final int sentCount;
  final int skippedCount;

  const SendEngagementExcuseResultModel({
    required this.sentCount,
    required this.skippedCount,
  });

  factory SendEngagementExcuseResultModel.fromJson(Map<String, dynamic> json) {
    return SendEngagementExcuseResultModel(
      sentCount: json['sent_count'] as int? ?? 0,
      skippedCount: json['skipped_count'] as int? ?? 0,
    );
  }
}
