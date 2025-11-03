-- =====================================================
-- Melodii - 私信系统修复脚本（清理并重建）
-- =====================================================
-- 这个脚本会先删除旧的函数和表，然后重新创建
-- =====================================================

-- 🧹 第一步：清理旧的函数和触发器
DROP FUNCTION IF EXISTS get_or_create_conversation(uuid, uuid) CASCADE;
DROP FUNCTION IF EXISTS update_conversation_last_message() CASCADE;
DROP TRIGGER IF EXISTS trigger_update_conversation_last_message ON messages;

-- 🧹 第二步：删除旧的 RLS 策略
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can create conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can view own messages" ON messages;
DROP POLICY IF EXISTS "Users can create messages" ON messages;
DROP POLICY IF EXISTS "Users can update own messages" ON messages;

-- 注意：不删除表，保留现有数据

-- ✅ 第三步：重新创建函数

-- 1. get_or_create_conversation 函数
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. 自动更新会话最后消息时间的函数
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

-- 3. 创建触发器
CREATE TRIGGER trigger_update_conversation_last_message
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION update_conversation_last_message();

-- ✅ 第四步：重新创建 RLS 策略

-- Conversations 策略
CREATE POLICY "Users can view own conversations"
    ON conversations FOR SELECT
    USING (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

CREATE POLICY "Users can create conversations"
    ON conversations FOR INSERT
    WITH CHECK (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

CREATE POLICY "Users can update own conversations"
    ON conversations FOR UPDATE
    USING (
        auth.uid() = participant1_id OR
        auth.uid() = participant2_id
    );

-- Messages 策略
CREATE POLICY "Users can view own messages"
    ON messages FOR SELECT
    USING (
        auth.uid() = sender_id OR
        auth.uid() = receiver_id
    );

CREATE POLICY "Users can create messages"
    ON messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can update own messages"
    ON messages FOR UPDATE
    USING (auth.uid() = receiver_id);

-- ✅ 验证修复结果
DO $$
BEGIN
    -- 检查函数
    IF EXISTS (
        SELECT 1 FROM pg_proc
        WHERE proname = 'get_or_create_conversation'
    ) THEN
        RAISE NOTICE '✅ get_or_create_conversation 函数已创建';
    ELSE
        RAISE EXCEPTION '❌ get_or_create_conversation 函数创建失败';
    END IF;

    -- 检查触发器
    IF EXISTS (
        SELECT 1 FROM pg_trigger
        WHERE tgname = 'trigger_update_conversation_last_message'
    ) THEN
        RAISE NOTICE '✅ 触发器已创建';
    ELSE
        RAISE EXCEPTION '❌ 触发器创建失败';
    END IF;

    -- 检查 RLS 策略
    IF EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'conversations'
        AND policyname = 'Users can view own conversations'
    ) THEN
        RAISE NOTICE '✅ RLS 策略已创建';
    ELSE
        RAISE EXCEPTION '❌ RLS 策略创建失败';
    END IF;

    RAISE NOTICE '🎉 私信系统修复完成！';
END $$;
