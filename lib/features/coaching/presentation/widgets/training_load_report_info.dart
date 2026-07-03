import '../../../../shared/widgets/report_info_button.dart';

const _trainingLoadDataSources = [
  'Yalnızca koşu aktiviteleri (Strava/Garmin ile kayıtlı running).',
  'Her koşudan: süre, ortalama tempo ve ortalama nabız.',
  'Profildeki VDOT değerinden türetilen eşik tempo (threshold pace).',
  'VDOT yoksa nabız hesabı için doğum tarihi.',
  'Son 90 günlük aktivite geçmişi.',
];

const _trainingLoadCalculations = [
  ReportInfoTerm(
    'TSS (Antrenman yükü puanı)',
    'Her koşunun yoğunluk ve süresine göre hesaplanan puan. Önce VDOT '
    'eşik temponuza göre tempo bazlı (rTSS); bu yoksa nabız bazlı '
    '(hrTSS) kullanılır. Formül: yoğunluk katsayısı² × süre (saat) × 100.',
  ),
  ReportInfoTerm(
    'CTL (Fitness)',
    'Günlük TSS değerlerinin ~42 günlük üstel ortalaması. Uzun vadeli '
    'kondisyon birikiminizi gösterir; ani sıçramalar yerine yavaş yükselir.',
  ),
  ReportInfoTerm(
    'ATL (Yorgunluk)',
    'Günlük TSS değerlerinin ~7 günlük üstel ortalaması. Son günlerdeki '
    'yüklenmenizi ve yorgunluğunuzu yansıtır.',
  ),
  ReportInfoTerm(
    'TSB (Form)',
    'CTL − ATL. Pozitif = dinç/hazır, negatif = yorgun. Renk kodunu '
    'belirlemez; form durumunu anlamak için kullanılır.',
  ),
  ReportInfoTerm(
    'ACWR',
    'Son 7 gün TSS toplamı ÷ (son 28 gün TSS toplamı ÷ 4). Kendi '
    'geçmişinize göre yük değişim oranınız; risk rengi buna dayanır.',
  ),
  ReportInfoTerm(
    '7g km',
    'Son 7 gündeki toplam koşu mesafesi. Bilgi amaçlıdır; güvenli/dikkat/'
    'risk durumu buna göre belirlenmez.',
  ),
];

const _trainingLoadExtraTerms = [
  ReportInfoTerm(
    'EWMA',
    'Üstel ağırlıklı hareketli ortalama. Yakın günler daha fazla, eski '
    'günler daha az ağırlık alır.',
  ),
  ReportInfoTerm(
    'Ramp %',
    'Bu haftanın TSS toplamının geçen haftaya göre yüzde değişimi. '
    'Ani artışlar sakatlık riskini yükseltir.',
  ),
];

const _trainingLoadRiskLogic = [
  'Renk kodu ACWR değerine göre belirlenir; toplam km veya başka '
  'sporcularla karşılaştırılmaz.',
  'Güvenli (yeşil): ACWR 0,8 – 1,3 — yükünüz geçmiş ortalamanızla uyumlu.',
  'Dikkat (turuncu): ACWR 1,3 – 1,5 veya 0,5 – 0,8 — yük artışı veya '
  'düşüşü sınırda.',
  'Risk (kırmızı): ACWR > 1,5 veya < 0,5 — son hafta yükünüz geçmişe '
  'göre çok arttı ya da çok azaldı.',
  'Örnek: Başkası senden fazla koşsa bile güvenli çıkabilir; o kişi '
  'yükünü kademeli artırmıştır (CTL yüksek, son hafta da dengeli).',
  'Örnek: Sen az koşsan bile riskli çıkabilirsin; uzun süre az koştuktan '
  'sonra birden yoğun bir hafta yaptıysan ACWR yükselir — risk, mutlak '
  'hacimden değil ani değişimden kaynaklanır.',
];

/// Performans Raporlari (koc paneli) bilgi icerigi.
const coachTrainingLoadReportInfo = ReportInfo(
  title: 'Performans Raporları',
  summary:
      'Sporcuların antrenman yükü ve formunu özetler. Kimin taze, kimin yorgun '
      'veya sakatlık riski altında olduğu ACWR oranına göre gösterilir — '
      'toplam kilometre veya başkalarıyla kıyaslamaya göre değil.',
  dataSources: _trainingLoadDataSources,
  calculations: _trainingLoadCalculations,
  terms: _trainingLoadExtraTerms,
  riskLogic: _trainingLoadRiskLogic,
  takeaways: [
    'Kırmızı (risk) sporcularda yükü azaltıp toparlanmaya öncelik verin.',
    'Yarış öncesi pozitif TSB hedeflenir (tapering).',
    'Sürekli düşük CTL, antrenman hacminin yetersiz olduğunu gösterir.',
    '7g km yüksek olsa bile ACWR dengedeyse güvenli görünebilirsiniz.',
  ],
);

/// Etkinlik yaris formu raporu — ayni hesaplama, etkinlik baglami.
const eventTrainingLoadReportInfo = ReportInfo(
  title: 'Etkinlik Yarış Formu',
  summary:
      'Yaklaşan bir yarışa katılacak sporcuların yarış öncesi form durumunu '
      'gösterir. Hesaplama Performans Raporları ile aynıdır; risk rengi '
      'ACWR oranına dayanır.',
  dataSources: _trainingLoadDataSources,
  calculations: _trainingLoadCalculations,
  terms: [
    ReportInfoTerm(
      'Taze → Yorgun',
      'Liste TSB (form) değerine göre sıralı: en dinçten en yorguna.',
    ),
    ..._trainingLoadExtraTerms,
  ],
  riskLogic: _trainingLoadRiskLogic,
  takeaways: [
    'Yarış öncesi pozitif TSB hedeflenir.',
    'Yorgun (negatif TSB) sporcular için yükü azaltmayı değerlendirin.',
    'Yüksek ACWR olan sporcuyu yakından takip edin.',
  ],
);

/// Tek sporcu PMC detay sayfasi.
const athleteTrainingLoadReportInfo = ReportInfo(
  title: 'Antrenman Yükü (PMC)',
  summary:
      'Tek sporcunun zaman içindeki form ve yük grafiğini gösterir. PMC, '
      'fitness ile yorgunluk dengesini izlemenin standart yoludur.',
  dataSources: _trainingLoadDataSources,
  calculations: _trainingLoadCalculations,
  terms: [
    ReportInfoTerm(
      'Haftalık km/yük',
      'Grafikteki haftalık toplam hacim çubukları; TSS ile birlikte '
      'yüklenme trendini gösterir.',
    ),
    ..._trainingLoadExtraTerms,
  ],
  riskLogic: _trainingLoadRiskLogic,
  takeaways: [
    'CTL yavaşça yükselmeli; ani sıçramalar sakatlık riski taşır.',
    'Yarış haftası TSB pozitife çekilir (tapering).',
    'Uzun süre çok negatif TSB aşırı yorgunluğa işaret eder.',
  ],
);
