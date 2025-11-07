-- Fix messaging constraints and add support for all message types
-- Run this in your Supabase SQL editor

-- 1. First, drop any existing constraint on message_type
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_type_check;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;

-- 2. Add a new constraint that supports all message types
ALTER TABLE public.messages ADD CONSTRAINT messages_message_type_check 
    CHECK (message_type IN ('text', 'image', 'video', 'voice', 'sticker'));

-- 3. Add voiceDuration column if it doesn't exist (for voice message duration tracking)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'voice_duration'
    ) THEN
        ALTER TABLE public.messages ADD COLUMN voice_duration REAL;
    END IF;
END $$;

-- 4. Add media_url column if it doesn't exist (for better media URL tracking)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'media_url'
    ) THEN
        ALTER TABLE public.messages ADD COLUMN media_url TEXT;
    END IF;
END $$;

-- 5. Add file_size column for media files
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'file_size'
    ) THEN
        ALTER TABLE public.messages ADD COLUMN file_size BIGINT;
    END IF;
END $$;

-- 6. Update existing data to use proper message types (if any exist with incorrect types)
UPDATE public.messages SET message_type = 'text' WHERE message_type IS NULL OR message_type = '';

-- 7. Create index for better performance on message type queries
CREATE INDEX IF NOT EXISTS idx_messages_type ON public.messages (message_type);
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created ON public.messages (conversation_id, created_at);

-- 8. Enable realtime for messages table if not already enabled
ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;

COMMENT ON TABLE public.messages IS 'Enhanced messaging table with support for text, image, video, voice, and sticker messages';
COMMENT ON COLUMN public.messages.message_type IS 'Type of message: text, image, video, voice, or sticker';
COMMENT ON COLUMN public.messages.voice_duration IS 'Duration of voice messages in seconds';
COMMENT ON COLUMN public.messages.media_url IS 'URL for media files (images, videos, voice, stickers)';
COMMENT ON COLUMN public.messages.file_size IS 'Size of media files in bytes';