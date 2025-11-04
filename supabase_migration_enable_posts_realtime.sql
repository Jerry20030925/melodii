-- Enable realtime on posts table for supabase_realtime publication
ALTER PUBLICATION supabase_realtime ADD TABLE posts;

-- Optional: verify
-- SELECT * FROM pg_publication_tables WHERE pubname = 'supabase_realtime';