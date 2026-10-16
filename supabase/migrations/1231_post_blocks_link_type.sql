-- =====================================================
-- 123: Post blocks — link tipi
-- =====================================================

ALTER TABLE public.post_blocks
DROP CONSTRAINT IF EXISTS valid_post_block_type;

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
    'link',
    'race_results'
));
