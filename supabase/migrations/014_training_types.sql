-- =====================================================
-- 014: Training Types - Antrenman Türleri
-- =====================================================
-- Koşu antrenmanı türleri ve açıklamaları

-- Training Types Tablosu
CREATE TABLE IF NOT EXISTS public.training_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    description TEXT NOT NULL,
    icon TEXT DEFAULT 'directions_run',
    color TEXT DEFAULT '#3B82F6',
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index
CREATE INDEX IF NOT EXISTS idx_training_types_sort_order 
    ON public.training_types(sort_order);

-- RLS Aktif Et
ALTER TABLE public.training_types ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir
CREATE POLICY "Anyone can view training types"
    ON public.training_types FOR SELECT
    USING (true);

-- Sadece admin yönetebilir
CREATE POLICY "Admins can manage training types"
    ON public.training_types FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role = 'super_admin'
        )
    );

-- Events tablosuna training_type_id ekle
ALTER TABLE public.events 
ADD COLUMN IF NOT EXISTS training_type_id UUID REFERENCES public.training_types(id) ON DELETE SET NULL;

-- Events tablosundan max_participants kaldır (opsiyonel - veriyi korumak için comment out)
-- ALTER TABLE public.events DROP COLUMN IF EXISTS max_participants;

-- Index
CREATE INDEX IF NOT EXISTS idx_events_training_type_id 
    ON public.events(training_type_id);

-- Event Group Programs tablosuna training_type_id ekle (grup bazlı antrenman türü)
ALTER TABLE public.event_group_programs 
ADD COLUMN IF NOT EXISTS training_type_id UUID REFERENCES public.training_types(id) ON DELETE SET NULL;

-- Index
CREATE INDEX IF NOT EXISTS idx_event_group_programs_training_type_id 
    ON public.event_group_programs(training_type_id);

-- Varsayılan antrenman türlerini ekle
INSERT INTO public.training_types (name, display_name, description, icon, color, sort_order) VALUES
(
    'recovery_run',
    'Recovery Run',
    'Yoğun antrenman sonrası toparlanma koşusu. Düşük tempoda, rahat nefes alarak yapılır. Kasları gevşetir ve kan dolaşımını artırır.',
    'self_improvement',
    '#10B981',
    1
),
(
    'easy_run',
    'Easy Run',
    'Temel dayanıklılık geliştiren rahat tempolu koşu. Konuşabilecek tempoda, aerobik kapasiteyi artırır. Haftalık antrenmanların büyük bölümünü oluşturur.',
    'directions_run',
    '#3B82F6',
    2
),
(
    'long_run',
    'Long Run',
    'Uzun mesafe dayanıklılığı için yapılan koşu. Haftalık en uzun antrenman olup, zihinsel ve fiziksel dayanıklılığı geliştirir.',
    'route',
    '#8B5CF6',
    3
),
(
    'progression_run',
    'Progression Run',
    'Yavaş başlayıp giderek hızlanan koşu. Vücudu yarış temposuna hazırlar ve negatif split stratejisini öğretir.',
    'trending_up',
    '#F59E0B',
    4
),
(
    'fartlek',
    'Fartlek',
    'İsveççe "hız oyunu" anlamına gelir. Yapılandırılmamış tempo değişiklikleri ile koşu. Hem eğlenceli hem de etkili bir antrenman.',
    'shuffle',
    '#EC4899',
    5
),
(
    'threshold',
    'Threshold (Tempo)',
    'Laktik eşik hızında yapılan koşu. "Rahatsız ama sürdürülebilir" tempoda, genellikle 20-40 dakika sürer. Yarış performansını artırır.',
    'speed',
    '#EF4444',
    6
),
(
    'interval',
    'Interval',
    'Yüksek yoğunluklu koşu ve dinlenme periyotlarından oluşur. VO2max ve hızı geliştirir. Örnek: 6x800m, 5x1000m.',
    'timer',
    '#F97316',
    7
),
(
    'repetition',
    'Repetition',
    'Kısa mesafeli, çok yüksek tempolu tekrarlar. Form ve koşu ekonomisini geliştirir. Tam dinlenme ile yapılır. Örnek: 8x200m, 10x400m.',
    'repeat',
    '#DC2626',
    8
),
(
    'hill_repeats',
    'Hill Repeats',
    'Yokuş yukarı koşu tekrarları. Bacak gücünü, koşu formunu ve zihinsel dayanıklılığı geliştirir. Sakatlık riskini azaltır.',
    'terrain',
    '#84CC16',
    9
),
(
    'marathon_pace',
    'Marathon Pace',
    'Hedef maraton temposunda yapılan koşu. Yarış günü stratejisini ve temposunu öğretir. Uzun koşuların bir bölümünde uygulanır.',
    'emoji_events',
    '#6366F1',
    10
)
ON CONFLICT (name) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description,
    icon = EXCLUDED.icon,
    color = EXCLUDED.color,
    sort_order = EXCLUDED.sort_order;
