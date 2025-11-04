-- ============================================
-- Migration: Add followers_count & following_count to users
-- Date: 2025-11-04
-- Description: 为 users 表增加关注/粉丝计数字段，并进行一次性回填

-- 1) 添加列（默认值为 0）
ALTER TABLE users
ADD COLUMN IF NOT EXISTS followers_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS following_count INTEGER DEFAULT 0;

COMMENT ON COLUMN users.followers_count IS '粉丝数（被多少人关注）';
COMMENT ON COLUMN users.following_count IS '关注数（关注了多少人）';

-- 2) 回填数据：根据 follows 表统计
-- 回填粉丝数：每个用户作为 following_id 被多少 follower 关注
UPDATE users u
SET followers_count = COALESCE(fc.cnt, 0)
FROM (
    SELECT following_id AS uid, COUNT(*) AS cnt
    FROM follows
    GROUP BY following_id
) fc
WHERE u.id = fc.uid;

-- 回填关注数：每个用户作为 follower_id 关注了多少人
UPDATE users u
SET following_count = COALESCE(fc.cnt, 0)
FROM (
    SELECT follower_id AS uid, COUNT(*) AS cnt
    FROM follows
    GROUP BY follower_id
) fc
WHERE u.id = fc.uid;

-- 3) 验证（可选）
-- SELECT id, followers_count, following_count FROM users ORDER BY followers_count DESC LIMIT 10;

-- 4) 索引（如需频繁排序/过滤，可添加；按需启用）
-- CREATE INDEX IF NOT EXISTS idx_users_followers_count ON users(followers_count);
-- CREATE INDEX IF NOT EXISTS idx_users_following_count ON users(following_count);

-- 完成