enum AppleWatchSendMode {
  autoSend,
  onDemand;

  static AppleWatchSendMode fromString(String? v) {
    switch (v) {
      case 'autoSend':
        return AppleWatchSendMode.autoSend;
      case 'onDemand':
        return AppleWatchSendMode.onDemand;
      default:
        return AppleWatchSendMode.autoSend;
    }
  }

  String get asString => switch (this) {
        AppleWatchSendMode.autoSend => 'autoSend',
        AppleWatchSendMode.onDemand => 'onDemand',
      };
}

class AppleWatchIntegrationSettings {
  final bool enabled;
  final AppleWatchSendMode mode;
  final DateTime? lastSyncAt;

  const AppleWatchIntegrationSettings({
    required this.enabled,
    required this.mode,
    this.lastSyncAt,
  });

  AppleWatchIntegrationSettings copyWith({
    bool? enabled,
    AppleWatchSendMode? mode,
    DateTime? lastSyncAt,
  }) {
    return AppleWatchIntegrationSettings(
      enabled: enabled ?? this.enabled,
      mode: mode ?? this.mode,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    );
  }

  static const defaults = AppleWatchIntegrationSettings(
    enabled: true,
    mode: AppleWatchSendMode.autoSend,
  );
}

