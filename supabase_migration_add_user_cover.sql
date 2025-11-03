-- Migration: Add cover_image_url to users table
-- Date: 2025-11-03
-- Description: 添加用户封面图功能

-- 添加封面图列
ALTER TABLE users
ADD COLUMN IF NOT EXISTS cover_image_url text;

-- 添加注释
COMMENT ON COLUMN users.cover_image_url IS '用户主页封面图 URL';

-- 验证迁移
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_name = 'users'
        AND column_name = 'cover_image_url'
    ) THEN
        RAISE NOTICE '✅ cover_image_url 列添加成功';
    END IF;
END $$;
