-- Supabase storage policies only (buckets already exist)
-- Run this in your Supabase SQL editor

-- NOTE: The buckets (audio, media, etc.) already exist in your Supabase
-- We only need to create the RLS policies

-- 1. Enable RLS on storage.objects (if not already enabled)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 2. Create simple, permissive policies for authenticated users

-- Policy for audio bucket (voice messages)
CREATE POLICY "Authenticated users can manage audio files" ON storage.objects
    FOR ALL USING (
        bucket_id = 'audio' AND 
        auth.role() = 'authenticated'
    );

-- Policy for media bucket (images, videos)  
CREATE POLICY "Authenticated users can manage media files" ON storage.objects
    FOR ALL USING (
        bucket_id = 'media' AND 
        auth.role() = 'authenticated'
    );

-- Policy for user-media bucket (avatars, covers)
CREATE POLICY "Authenticated users can manage user-media files" ON storage.objects
    FOR ALL USING (
        bucket_id = 'user-media' AND 
        auth.role() = 'authenticated'
    );

-- Policy for chat-media bucket (chat attachments)
CREATE POLICY "Authenticated users can manage chat-media files" ON storage.objects
    FOR ALL USING (
        bucket_id = 'chat-media' AND 
        auth.role() = 'authenticated'
    );

-- Policy for public-assets bucket (public content)
CREATE POLICY "Anyone can view public-assets" ON storage.objects
    FOR SELECT USING (bucket_id = 'public-assets');

CREATE POLICY "Authenticated users can manage public-assets" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'public-assets' AND 
        auth.role() = 'authenticated'
    );

-- Grant storage permissions
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;