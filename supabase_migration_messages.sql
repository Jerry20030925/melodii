-- =====================================================
-- Melodii - 私信系统迁移脚本
-- =====================================================
-- 创建时间: 2025-10-30
-- 说明: 创建实时私信所需的表、索引和RLS策略
-- =====================================================

-- 1. 创建 conversations 表（会话表）
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    participant1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- 确保两个用户之间只有一个会话
    UNIQUE(participant1_id, participant2_id),

    -- 防止自己和自己对话
    CHECK (participant1_id != participant2_id),

    -- 确保participant1_id < participant2_id（规范化存储）
    CHECK (participant1_id < participant2_id)
);

-- 2. 创建 messages 表（消息表）
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type VARCHAR(20) NOT NULL DEFAULT 'text',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- 消息类型约束
    CHECK (message_type IN ('text', 'image', 'voice', 'system'))
);

-- 3. 创建索引优化查询性能
CREATE INDEX IF NOT EXISTS idx_conversations_participant1 ON conversations(participant1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_participant2 ON conversations(participant2_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message ON conversations(last_message_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_conversation ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_messages_sender ON messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_messages_receiver ON messages(receiver_id);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_is_read ON messages(is_read) WHERE is_read = false;

-- 4. 启用行级安全 (Row Level Security)
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 5. 删除可能存在的旧策略
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON conversations;

DROP POLICY IF EXISTS "Users can view own messages" ON messages;
DROP POLICY IF EXISTS "Users can create messages" ON messages;
DROP POLICY IF EXISTS "Users can update own messages" ON messages;

-- 6. 创建 RLS 策略 - Conversations

-- 允许用户查看自己参与的会话
CREATE POLICY "Users can view own conversations"
    ON conversations FOR SELECT
    USING (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

-- 允许用户创建会话
CREATE POLICY "Users can create conversations"
    ON conversations FOR INSERT
    WITH CHECK (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

-- 允许用户更新自己参与的会话
CREATE POLICY "Users can update own conversations"
    ON conversations FOR UPDATE
    USING (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

-- 7. 创建 RLS 策略 - Messages

-- 允许用户查看自己发送或接收的消息
CREATE POLICY "Users can view own messages"
    ON messages FOR SELECT
    USING (
        auth.uid() = sender_id OR
        auth.uid() = receiver_id
    );

-- 只允许用户创建自己发送的消息
CREATE POLICY "Users can create messages"
    ON messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

-- 只允许接收者更新消息（标记已读）
CREATE POLICY "Users can update own messages"
    ON messages FOR UPDATE
    USING (auth.uid() = receiver_id);

-- 8. 创建函数：自动更新会话的最后消息时间
CREATE OR REPLACE FUNCTION update_conversation_last_message()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE conversations
    SET
        last_message_at = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9. 创建触发器：新消息时更新会话
DROP TRIGGER IF EXISTS trigger_update_conversation_last_message ON messages;
CREATE TRIGGER trigger_update_conversation_last_message
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_last_message();

-- 10. 创建函数：获取或创建会话
CREATE OR REPLACE FUNCTION get_or_create_conversation(
    user1_id UUID,
    user2_id UUID
)
RETURNS UUID AS $$
DECLARE
    conv_id UUID;
    p1_id UUID;
    p2_id UUID;
BEGIN
    -- 确保 participant1_id < participant2_id
    IF user1_id < user2_id THEN
        p1_id := user1_id;
        p2_id := user2_id;
    ELSE
        p1_id := user2_id;
        p2_id := user1_id;
    END IF;

    -- 尝试查找现有会话
    SELECT id INTO conv_id
    FROM conversations
    WHERE participant1_id = p1_id AND participant2_id = p2_id;

    -- 如果不存在，创建新会话
    IF conv_id IS NULL THEN
        INSERT INTO conversations (participant1_id, participant2_id)
        VALUES (p1_id, p2_id)
        RETURNING id INTO conv_id;
    END IF;

    RETURN conv_id;
END;
$$ LANGUAGE plpgsql;

-- 11. 启用 Realtime（实时订阅）
-- 启用conversations表的实时功能
ALTER PUBLICATION supabase_realtime ADD TABLE conversations;

-- 启用messages表的实时功能
ALTER PUBLICATION supabase_realtime ADD TABLE messages;

-- =====================================================
-- 测试查询（可选）
-- =====================================================

-- 查看表结构
-- SELECT * FROM information_schema.columns WHERE table_name IN ('conversations', 'messages');

-- 查看索引
-- SELECT * FROM pg_indexes WHERE tablename IN ('conversations', 'messages');

-- 查看RLS策略
-- SELECT * FROM pg_policies WHERE tablename IN ('conversations', 'messages');

-- 测试获取或创建会话
-- SELECT get_or_create_conversation('user1-uuid', 'user2-uuid');

-- =====================================================
-- 回滚脚本（如需要删除表）
-- =====================================================
-- DROP TRIGGER IF EXISTS trigger_update_conversation_last_message ON messages;
-- DROP FUNCTION IF EXISTS update_conversation_last_message();
-- DROP FUNCTION IF EXISTS get_or_create_conversation(UUID, UUID);
-- DROP TABLE IF EXISTS messages CASCADE;
-- DROP TABLE IF EXISTS conversations CASCADE;
