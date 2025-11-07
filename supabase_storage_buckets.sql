-- Supabase storage buckets and RLS policies
-- Run this in your Supabase SQL editor

-- 1. Create storage buckets if they don't exist
INSERT INTO storage.buckets (id, name, public) 
VALUES 
    ('media', 'media', true),
    ('audio', 'audio', true)
ON CONFLICT (id) DO UPDATE SET
    public = EXCLUDED.public;

-- 2. Enable RLS on storage.objects
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3. Drop existing storage policies to avoid conflicts
DROP POLICY IF EXISTS "Users can upload media files" ON storage.objects;
DROP POLICY IF EXISTS "Users can view media files" ON storage.objects; 
DROP POLICY IF EXISTS "Users can update their media files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their media files" ON storage.objects;

DROP POLICY IF EXISTS "Users can upload audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can view audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their audio files" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their audio files" ON storage.objects;

DROP POLICY IF EXISTS "Public can view media files" ON storage.objects;
DROP POLICY IF EXISTS "Public can view audio files" ON storage.objects;

-- 4. Create comprehensive storage policies

-- Media bucket policies (for images, videos, avatars)
CREATE POLICY "Users can upload media files" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'media' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Anyone can view media files" ON storage.objects
    FOR SELECT USING (bucket_id = 'media');

CREATE POLICY "Users can update their media files" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'media' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can delete their media files" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'media' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

-- Audio bucket policies (for voice messages)
CREATE POLICY "Users can upload audio files" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'audio' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Anyone can view audio files" ON storage.objects
    FOR SELECT USING (bucket_id = 'audio');

CREATE POLICY "Users can update their audio files" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'audio' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users can delete their audio files" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'audio' AND 
        auth.uid()::text = (storage.foldername(name))[1]
    );

-- 5. Alternative simpler policies if the above don't work
-- Uncomment these if you get path parsing errors

-- CREATE POLICY "Authenticated users can manage media" ON storage.objects
--     FOR ALL USING (bucket_id = 'media' AND auth.role() = 'authenticated');

-- CREATE POLICY "Authenticated users can manage audio" ON storage.objects  
--     FOR ALL USING (bucket_id = 'audio' AND auth.role() = 'authenticated');

-- 6. Grant storage permissions
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;