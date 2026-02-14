-- =====================================================
-- 010: Event Info Blocks - Notion Benzeri Dinamik İçerik
-- =====================================================
-- Etkinlikler için zengin içerik blokları (program, uyarılar, bilgiler vb.)

-- Event Info Blocks Tablosu
CREATE TABLE IF NOT EXISTS public.event_info_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
    type TEXT NOT NULL DEFAULT 'text',
    content TEXT NOT NULL,
    sub_content TEXT,
    color TEXT,
    icon TEXT,
    order_index INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    
    -- Type constraint
    CONSTRAINT valid_block_type CHECK (type IN (
        'header',
        'subheader', 
        'schedule_item',
        'warning',
        'info',
        'tip',
        'text',
        'quote',
        'list_item',
        'checklist_item',
        'divider'
    ))
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_event_info_blocks_event_id 
    ON public.event_info_blocks(event_id);
CREATE INDEX IF NOT EXISTS idx_event_info_blocks_order 
    ON public.event_info_blocks(event_id, order_index);

-- RLS Aktif Et
ALTER TABLE public.event_info_blocks ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (yayınlanmış etkinlikler için)
CREATE POLICY "Anyone can view info blocks of published events"
    ON public.event_info_blocks FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.events 
            WHERE events.id = event_info_blocks.event_id 
            AND events.status = 'published'
        )
    );

-- Admin ve Coach oluşturabilir
CREATE POLICY "Admins and coaches can create info blocks"
    ON public.event_info_blocks FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin ve Coach güncelleyebilir
CREATE POLICY "Admins and coaches can update info blocks"
    ON public.event_info_blocks FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Admin ve Coach silebilir
CREATE POLICY "Admins and coaches can delete info blocks"
    ON public.event_info_blocks FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM public.user_roles
            WHERE user_roles.user_id = auth.uid()
            AND user_roles.role IN ('super_admin', 'coach')
        )
    );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_event_info_block_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER event_info_block_updated_at
    BEFORE UPDATE ON public.event_info_blocks
    FOR EACH ROW EXECUTE FUNCTION update_event_info_block_updated_at();

-- Yorum: Blok Türleri
-- header: Ana başlık (örn: "CUMARTESİ 04.04.2026")
-- subheader: Alt başlık
-- schedule_item: Zaman çizelgesi (content: saat, sub_content: açıklama)
-- warning: Kırmızı uyarı kutusu
-- info: Mavi bilgi kutusu
-- tip: Yeşil ipucu kutusu
-- text: Normal paragraf
-- quote: Alıntı
-- list_item: Liste öğesi
-- checklist_item: Kontrol listesi öğesi
-- divider: Ayırıcı çizgi
