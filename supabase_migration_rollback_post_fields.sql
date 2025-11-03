-- Rollback Migration: Remove mood_tags, city, and is_anonymous from posts table
-- Date: 2025-11-03
-- Description: 回滚情绪标签、城市信息和匿名发布功能

-- 警告：此操作将删除列及其所有数据！
-- Warning: This will drop the columns and all their data!

-- 删除索引
DROP INDEX IF EXISTS idx_posts_mood_tags;
DROP INDEX IF EXISTS idx_posts_city;
DROP INDEX IF EXISTS idx_posts_anonymous;

-- 删除列
ALTER TABLE posts DROP COLUMN IF EXISTS mood_tags;
ALTER TABLE posts DROP COLUMN IF EXISTS city;
ALTER TABLE posts DROP COLUMN IF EXISTS is_anonymous;

-- 验证回滚
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'mood_tags'
    ) THEN
        RAISE NOTICE '✅ mood_tags 列已删除';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'city'
    ) THEN
        RAISE NOTICE '✅ city 列已删除';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'posts'
        AND column_name = 'is_anonymous'
    ) THEN
        RAISE NOTICE '✅ is_anonymous 列已删除';
    END IF;
END $$;
