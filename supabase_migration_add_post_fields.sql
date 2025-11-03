-- Migration: Add mood_tags, city, and is_anonymous to posts table
-- Date: 2025-11-03
-- Description: 支持情绪标签、城市信息和匿名发布功能

-- 添加情绪标签列（数组类型）
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS mood_tags text[] DEFAULT '{}';

-- 添加城市列
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS city text;

-- 添加匿名发布标识列
ALTER TABLE posts
ADD COLUMN IF NOT EXISTS is_anonymous boolean DEFAULT false;

-- 添加注释
COMMENT ON COLUMN posts.mood_tags IS '情绪标签数组，如：开心、孤独、发现美好';
COMMENT ON COLUMN posts.city IS '发布时的城市信息（可选）';
COMMENT ON COLUMN posts.is_anonymous IS '是否匿名发布（隐藏用户信息）';

-- 为新列创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_posts_mood_tags ON posts USING GIN(mood_tags);
CREATE INDEX IF NOT EXISTS idx_posts_city ON posts(city) WHERE city IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_posts_anonymous ON posts(is_anonymous) WHERE is_anonymous = true;

-- 验证迁移
DO $$
BEGIN
    -- 检查列是否存在
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'mood_tags'
    ) THEN
        RAISE NOTICE '✅ mood_tags 列添加成功';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'city'
    ) THEN
        RAISE NOTICE '✅ city 列添加成功';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'is_anonymous'
    ) THEN
        RAISE NOTICE '✅ is_anonymous 列添加成功';
    END IF;
END $$;
