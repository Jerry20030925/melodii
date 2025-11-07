-- 创建主页访问记录表
CREATE TABLE IF NOT EXISTS profile_visits (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visitor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    visited_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- 确保同一访问者在短时间内不重复记录（24小时内只记录一次）
    CONSTRAINT unique_visitor_per_day UNIQUE (profile_owner_id, visitor_id, DATE(visited_at))
);

-- 创建索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_profile_visits_owner ON profile_visits(profile_owner_id, visited_at DESC);
CREATE INDEX IF NOT EXISTS idx_profile_visits_visitor ON profile_visits(visitor_id);

-- 启用行级安全（RLS）
ALTER TABLE profile_visits ENABLE ROW LEVEL SECURITY;

-- 策略：用户只能查看自己主页的访问记录
CREATE POLICY "Users can view visits to their own profile"
ON profile_visits
FOR SELECT
USING (auth.uid() = profile_owner_id);

-- 策略：任何登录用户都可以创建访问记录
CREATE POLICY "Authenticated users can create visit records"
ON profile_visits
FOR INSERT
WITH CHECK (auth.uid() = visitor_id);

-- 策略：用户可以删除访问自己主页的记录
CREATE POLICY "Users can delete visits to their own profile"
ON profile_visits
FOR DELETE
USING (auth.uid() = profile_owner_id);

-- 注释
COMMENT ON TABLE profile_visits IS '主页访问记录表';
COMMENT ON COLUMN profile_visits.profile_owner_id IS '主页所有者ID';
COMMENT ON COLUMN profile_visits.visitor_id IS '访问者ID';
COMMENT ON COLUMN profile_visits.visited_at IS '访问时间';
