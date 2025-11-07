-- Simple test to check if messaging tables work
-- Run this one line at a time in Supabase SQL editor

-- Test 1: Check if tables exist
SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'conversations'
);

SELECT EXISTS (
    SELECT FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name = 'messages'  
);

-- Test 2: Check current user
SELECT auth.uid() as current_user_id;

-- Test 3: Try to see conversations (should show existing conversations)
SELECT id, participant1_id, participant2_id FROM public.conversations LIMIT 5;

-- Test 4: Try to see messages (should show existing messages)  
SELECT id, conversation_id, sender_id, content, message_type FROM public.messages LIMIT 5;