-- =====================================================
-- 047: Add race_results post block type
-- =====================================================
-- Yarış sonuçlarını post içinde göstermek için yeni blok tipi

-- Mevcut constraint'i kaldır
ALTER TABLE public.post_blocks 
DROP CONSTRAINT IF EXISTS valid_post_block_type;

-- Yeni constraint'i ekle (race_results ile)
ALTER TABLE public.post_blocks 
ADD CONSTRAINT valid_post_block_type CHECK (type IN (
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
    'divider',
    'image',
    'race_results'
));
