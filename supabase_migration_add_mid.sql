-- 为 users 表添加唯一的 MID 字段（对外展示的用户编号）
ALTER TABLE users
ADD COLUMN IF NOT EXISTS mid TEXT UNIQUE;

-- 为已有用户生成 MID（前缀 M + 随机8位）
UPDATE users
SET mid = 'M' || replace(substr(uuid_generate_v4()::text, 1, 8), '-', '')
WHERE mid IS NULL;
