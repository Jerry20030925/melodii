-- =====================================================
-- Melodii - Follows 表迁移脚本
-- =====================================================
-- 创建时间: 2025-10-30
-- 说明: 创建关注系统所需的 follows 表及相关索引和RLS策略
-- =====================================================

-- 1. 创建 follows 表
CREATE TABLE IF NOT EXISTS follows (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- 确保同一对用户关系唯一
    UNIQUE(follower_id, following_id),

    -- 防止自己关注自己
    CHECK (follower_id != following_id)
);

-- 2. 创建索引以优化查询性能
CREATE INDEX IF NOT EXISTS idx_follows_follower ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following ON follows(following_id);
CREATE INDEX IF NOT EXISTS idx_follows_created_at ON follows(created_at DESC);

-- 3. 启用行级安全 (Row Level Security)
ALTER TABLE follows ENABLE ROW LEVEL SECURITY;

-- 4. 删除可能存在的旧策略
DROP POLICY IF EXISTS "Anyone can view follows" ON follows;
DROP POLICY IF EXISTS "Users can create own follows" ON follows;
DROP POLICY IF EXISTS "Users can delete own follows" ON follows;

-- 5. 创建 RLS 策略

-- 允许所有人查看关注关系（用于显示粉丝数、关注数等）
CREATE POLICY "Anyone can view follows"
    ON follows FOR SELECT
    USING (true);

-- 只允许用户创建自己的关注关系（follower_id 必须是当前用户）
CREATE POLICY "Users can create own follows"
    ON follows FOR INSERT
    WITH CHECK (auth.uid() = follower_id);

-- 只允许用户删除自己的关注关系（follower_id 必须是当前用户）
CREATE POLICY "Users can delete own follows"
    ON follows FOR DELETE
    USING (auth.uid() = follower_id);

-- =====================================================
-- 测试查询（可选）
-- =====================================================

-- 查看表结构
-- SELECT * FROM information_schema.columns WHERE table_name = 'follows';

-- 查看索引
-- SELECT * FROM pg_indexes WHERE tablename = 'follows';

-- 查看RLS策略
-- SELECT * FROM pg_policies WHERE tablename = 'follows';

-- =====================================================
-- 回滚脚本（如需要删除表）
-- =====================================================
-- DROP TABLE IF EXISTS follows CASCADE;
