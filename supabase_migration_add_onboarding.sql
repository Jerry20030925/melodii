-- ============================================
-- Melodii - 添加用户引导字段的迁移脚本
-- ============================================

-- 为users表添加新字段
ALTER TABLE users
ADD COLUMN IF NOT EXISTS birthday TIMESTAMP WITH TIME ZONE,
ADD COLUMN IF NOT EXISTS interests TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS is_onboarding_completed BOOLEAN DEFAULT FALSE;

-- 为现有用户设置默认值
UPDATE users
SET
    interests = '{}',
    is_onboarding_completed = FALSE
WHERE interests IS NULL OR is_onboarding_completed IS NULL;

-- ============================================
-- 完成
-- ============================================

-- 迁移完成！
-- 说明：
-- 1. birthday: 用户生日（可选）
-- 2. interests: 用户兴趣爱好数组
-- 3. is_onboarding_completed: 是否完成新用户引导
