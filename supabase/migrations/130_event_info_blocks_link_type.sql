-- =====================================================
-- 130: Event info blocks — link tipi
-- =====================================================

ALTER TABLE public.event_info_blocks
DROP CONSTRAINT IF EXISTS valid_block_type;

ALTER TABLE public.event_info_blocks
ADD CONSTRAINT valid_block_type CHECK (type IN (
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
    'link'
));
