-- 自定义表情包表
CREATE TABLE IF NOT EXISTS custom_stickers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_custom_stickers_user_id ON custom_stickers(user_id);
CREATE INDEX IF NOT EXISTS idx_custom_stickers_created_at ON custom_stickers(created_at DESC);

-- RLS 策略
ALTER TABLE custom_stickers ENABLE ROW LEVEL SECURITY;

-- 用户可以查看自己的表情包
CREATE POLICY "Users can view own stickers"
ON custom_stickers FOR SELECT
USING (auth.uid() = user_id);

-- 用户可以创建自己的表情包
CREATE POLICY "Users can create own stickers"
ON custom_stickers FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- 用户可以删除自己的表情包
CREATE POLICY "Users can delete own stickers"
ON custom_stickers FOR DELETE
USING (auth.uid() = user_id);

-- 注释
COMMENT ON TABLE custom_stickers IS '自定义表情包表';
COMMENT ON COLUMN custom_stickers.id IS '表情包ID';
COMMENT ON COLUMN custom_stickers.user_id IS '用户ID';
COMMENT ON COLUMN custom_stickers.image_url IS '表情包图片URL';
COMMENT ON COLUMN custom_stickers.name IS '表情包名称（可选）';
COMMENT ON COLUMN custom_stickers.created_at IS '创建时间';
