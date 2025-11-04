-- Migration: Add last_mid_update to users table
-- Date: 2025-01-01
-- Description: 添加MID修改时间记录字段，用于控制修改频率

-- 添加last_mid_update列
ALTER TABLE users
ADD COLUMN IF NOT EXISTS last_mid_update TIMESTAMP WITH TIME ZONE;

-- 为现有用户设置默认值（如果已有MID，设置为6个月前，允许立即修改）
UPDATE users
SET last_mid_update = NOW() - INTERVAL '6 months'
WHERE mid IS NOT NULL AND last_mid_update IS NULL;

-- 添加注释
COMMENT ON COLUMN users.last_mid_update IS '上次MID修改时间，用于控制修改频率（每半年一次）';

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_users_last_mid_update ON users(last_mid_update);