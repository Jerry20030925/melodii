ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated users can manage audio files" ON storage.objects
FOR ALL USING (
    bucket_id = 'audio' AND 
    auth.role() = 'authenticated'
);

CREATE POLICY "Authenticated users can manage media files" ON storage.objects
FOR ALL USING (
    bucket_id = 'media' AND 
    auth.role() = 'authenticated'
);

GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;