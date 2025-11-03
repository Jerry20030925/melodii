-- 会话表
CREATE TABLE IF NOT EXISTS conversations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    participant1_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    participant2_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    last_message_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(participant1_id, participant2_id)
);

-- 消息表（如果schema里已存在则跳过此段）
CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    conversation_id UUID REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    message_type TEXT DEFAULT 'text',
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 会话辅助索引
CREATE INDEX IF NOT EXISTS idx_conversations_p1 ON conversations(participant1_id);
CREATE INDEX IF NOT EXISTS idx_conversations_p2 ON conversations(participant2_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON conversations(last_message_at DESC);

-- 消息辅助索引
CREATE INDEX IF NOT EXISTS idx_messages_conversation_id ON messages(conversation_id);

-- get_or_create_conversation 函数（保证两人之间只有一个会话）
CREATE OR REPLACE FUNCTION get_or_create_conversation(user1_id UUID, user2_id UUID)
RETURNS UUID AS $$
DECLARE
    conv_id UUID;
    p1 UUID := LEAST(user1_id, user2_id);
    p2 UUID := GREATEST(user1_id, user2_id);
BEGIN
    SELECT id INTO conv_id FROM conversations
    WHERE participant1_id = p1 AND participant2_id = p2
    LIMIT 1;

    IF conv_id IS NULL THEN
        INSERT INTO conversations(participant1_id, participant2_id)
        VALUES (p1, p2)
        RETURNING id INTO conv_id;
    END IF;

    RETURN conv_id;
END;
$$ LANGUAGE plpgsql;

-- RLS 开启
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;

-- 注意：Postgres 不支持 CREATE POLICY IF NOT EXISTS，用 DO 块保证幂等
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'conversations' AND policyname = '查看参与的会话'
    ) THEN
        CREATE POLICY "查看参与的会话" ON conversations FOR SELECT USING (
          participant1_id = auth.uid() OR participant2_id = auth.uid()
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'conversations' AND policyname = '插入自己参与的会话'
    ) THEN
        CREATE POLICY "插入自己参与的会话" ON conversations FOR INSERT WITH CHECK (
          participant1_id = auth.uid() OR participant2_id = auth.uid()
        );
    END IF;
END $$;

-- 若 messages 表由本项目维护 RLS：
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'messages' AND policyname = '查看会话消息'
    ) THEN
        CREATE POLICY "查看会话消息" ON messages FOR SELECT USING (
          sender_id = auth.uid() OR receiver_id = auth.uid()
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public' AND tablename = 'messages' AND policyname = '发送消息'
    ) THEN
        CREATE POLICY "发送消息" ON messages FOR INSERT WITH CHECK (
          sender_id = auth.uid()
        );
    END IF;
END $$;
