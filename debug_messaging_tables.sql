-- Debug script to check messaging table status
-- Run this in your Supabase SQL editor

-- 1. Check if tables exist
SELECT table_name, table_type 
FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('conversations', 'messages');

-- 2. Check conversations table structure
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'conversations' 
AND table_schema = 'public';

-- 3. Check messages table structure  
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'messages' 
AND table_schema = 'public';

-- 4. Check RLS policies on messages table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'messages';

-- 5. Check RLS policies on conversations table
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE tablename = 'conversations';

-- 6. Test basic insert (will show detailed error if RLS blocks it)
-- Comment this out if you don't want to test insert
-- INSERT INTO public.messages (conversation_id, sender_id, receiver_id, content, message_type) 
-- VALUES ('test-conv-id', auth.uid(), auth.uid(), 'test message', 'text');