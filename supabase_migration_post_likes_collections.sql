-- Supabase migration for post likes and collections tables
-- Run this in your Supabase SQL editor

-- 1. Create post_likes table
CREATE TABLE IF NOT EXISTS public.post_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure one like per user per post
    UNIQUE(user_id, post_id)
);

-- 2. Create post_collections table
CREATE TABLE IF NOT EXISTS public.post_collections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Ensure one collection per user per post
    UNIQUE(user_id, post_id)
);

-- 3. Enable RLS (Row Level Security)
ALTER TABLE public.post_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.post_collections ENABLE ROW LEVEL SECURITY;

-- 4. Create RLS policies for post_likes
CREATE POLICY "Users can view all post likes" ON public.post_likes
    FOR SELECT USING (true);

CREATE POLICY "Users can insert their own likes" ON public.post_likes
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own likes" ON public.post_likes
    FOR DELETE USING (auth.uid() = user_id);

-- 5. Create RLS policies for post_collections
CREATE POLICY "Users can view all post collections" ON public.post_collections
    FOR SELECT USING (true);

CREATE POLICY "Users can insert their own collections" ON public.post_collections
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own collections" ON public.post_collections
    FOR DELETE USING (auth.uid() = user_id);

-- 6. Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON public.post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_post_id ON public.post_likes(post_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_created_at ON public.post_likes(created_at);

CREATE INDEX IF NOT EXISTS idx_post_collections_user_id ON public.post_collections(user_id);
CREATE INDEX IF NOT EXISTS idx_post_collections_post_id ON public.post_collections(post_id);
CREATE INDEX IF NOT EXISTS idx_post_collections_created_at ON public.post_collections(created_at);

-- 7. Create functions to get counts
CREATE OR REPLACE FUNCTION get_post_like_count(post_uuid UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INTEGER 
        FROM public.post_likes 
        WHERE post_id = post_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION get_post_collection_count(post_uuid UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)::INTEGER 
        FROM public.post_collections 
        WHERE post_id = post_uuid
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 8. Grant necessary permissions
GRANT SELECT, INSERT, DELETE ON public.post_likes TO authenticated;
GRANT SELECT, INSERT, DELETE ON public.post_collections TO authenticated;
GRANT EXECUTE ON FUNCTION get_post_like_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_post_collection_count(UUID) TO authenticated;