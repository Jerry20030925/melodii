TS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'messages' AND column_name = 'text'
    ) THEN
        EXECUTE 'UPDATE messages SET content = COALESCE(content, text) WHERE content IS NULL';
    END IF;
END $$;

-- 3) 为历史消息回填 conversation_id
UPDATE messages
SET conversation_id = get_or_create_conversation(sender_id, receiver_id)
WHERE conversation_id IS NULL;

-- 4) 索引
CREATE INDEX IF NOT EXISTS idx_messages_conv_id ON messages(conversation_id);

-- 5) 插入消息时自动更新会话的最后消息时间
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.conversation_id IS NOT NULL THEN
        UPDATE conversations SET last_message_at = NOW() WHERE id = NEW.conversation_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_after_message_insert ON messages;
CREATE TRIGGER trg_after_message_insert
AFTER INSERT ON messages
FOR EACH ROW EXECUTE FUNCTION update_conversation_last_message();
-- 修复 messages 表缺少列导致“conversation_id 不存在”的问题

-- 1) 补充列
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS content TEXT,
ADD COLUMN IF NOT EXISTS message_type TEXT DEFAULT 'text';

-- 2) 将旧列 text 的数据回填到 content（若存在旧结构）
DO $$
BEGIN
    IF EXIS