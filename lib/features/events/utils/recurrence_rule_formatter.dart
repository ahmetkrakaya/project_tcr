/// iCal RRULE metnini kullanıcıya gösterilecek Türkçe özet metne çevirir.
String formatRecurrenceRule(String? rule) {
  if (rule == null || rule.trim().isEmpty) return 'Bilinmiyor';

  final upper = rule.toUpperCase();
  if (upper.contains('FREQ=WEEKLY') && upper.contains('BYDAY=')) {
    const dayCodes = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];
    const dayNames = [
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    final match = RegExp(r'BYDAY=([A-Z,]+)', caseSensitive: false).firstMatch(rule);
    if (match != null) {
      final days = match
          .group(1)!
          .split(',')
          .map((c) => c.trim().toUpperCase())
          .map((c) {
            final i = dayCodes.indexOf(c);
            return i >= 0 ? dayNames[i] : c;
          })
          .toList();
      if (days.length == 1) {
        return 'Her hafta ${days.first}';
      }
      return 'Her hafta ${days.join(', ')}';
    }
    return 'Her hafta';
  }

  if (upper.contains('FREQ=MONTHLY') && upper.contains('BYMONTHDAY=')) {
    final match = RegExp(r'BYMONTHDAY=(\d+)', caseSensitive: false).firstMatch(rule);
    if (match != null) {
      return 'Her ayın ${match.group(1)}. günü';
    }
    return 'Her ay';
  }

  if (upper.contains('FREQ=YEARLY')) {
    const monthNames = [
      '',
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    final monthMatch = RegExp(r'BYMONTH=(\d+)', caseSensitive: false).firstMatch(rule);
    final dayMatch = RegExp(r'BYMONTHDAY=(\d+)', caseSensitive: false).firstMatch(rule);
    if (monthMatch != null && dayMatch != null) {
      final month = int.tryParse(monthMatch.group(1)!);
      final day = dayMatch.group(1);
      if (month != null && month >= 1 && month <= 12) {
        return 'Her yıl ${monthNames[month]} $day';
      }
    }
    return 'Her yıl';
  }

  return rule;
}
