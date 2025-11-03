# 🔧 私信功能修复指南

## 问题诊断

**错误信息**：
```
打开会话失败：Could not find the function public.get_or_create_conversation(user1_id, user2_id) in the schema cache
```

**根本原因**：
数据库中缺少 `get_or_create_conversation` 函数。虽然 App 代码已经准备好，但数据库迁移脚本还没有执行。

---

## ✅ 修复步骤

### 第一步：执行数据库迁移

1. **登录 Supabase Dashboard**
   - 打开 https://supabase.com/dashboard
   - 选择你的项目

2. **打开 SQL Editor**
   - 左侧菜单点击 "SQL Editor"
   - 点击 "+ New query"

3. **执行迁移脚本**
   - 打开项目文件：`EXECUTE_THIS_MIGRATION.sql`
   - 复制全部内容
   - 粘贴到 SQL Editor
   - 点击 "Run" 按钮

4. **验证迁移成功**

   执行完成后，你应该看到类似以下的输出：
   ```
   ✅ conversations 表已创建
   ✅ messages 表已创建
   ✅ get_or_create_conversation 函数已创建
   ✅ RLS 策略已创建
   🎉 私信系统迁移完成！
   ```

### 第二步：验证数据库表和函数

在 SQL Editor 中运行以下查询验证：

```sql
-- 查看 conversations 表
SELECT * FROM information_schema.tables WHERE table_name = 'conversations';

-- 查看 messages 表
SELECT * FROM information_schema.tables WHERE table_name = 'messages';

-- 查看 get_or_create_conversation 函数
SELECT proname, pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'get_or_create_conversation';

-- 查看 RLS 策略
SELECT * FROM pg_policies WHERE tablename IN ('conversations', 'messages');
```

### 第三步：重启 App 测试

1. **重新构建并安装 App**（如果还没构建最新版）
   ```bash
   xcodebuild -project Melodii.xcodeproj -scheme Melodii -sdk iphonesimulator build
   ```

2. **在真机或模拟器上测试**
   - 打开 App
   - 进入 "Connect" 页面
   - 点击任意用户的 "私信" 按钮
   - 应该能成功打开聊天界面

---

## 🎯 功能说明

### 私信系统架构

```
App (Swift)
  ↓
SupabaseService.getOrCreateConversation()
  ↓
调用 RPC: get_or_create_conversation(user1_id, user2_id)
  ↓
返回 conversation_id
  ↓
打开聊天界面
```

### 数据库结构

#### 1. conversations 表
```sql
- id: UUID (主键)
- participant1_id: UUID (参与者1，确保 < participant2_id)
- participant2_id: UUID (参与者2)
- last_message_at: TIMESTAMP (最后消息时间)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
- UNIQUE(participant1_id, participant2_id) -- 确保两人只有一个会话
```

#### 2. messages 表
```sql
- id: UUID (主键)
- conversation_id: UUID (关联会话)
- sender_id: UUID (发送者)
- receiver_id: UUID (接收者)
- content: TEXT (消息内容)
- message_type: VARCHAR (text/image/voice/system)
- is_read: BOOLEAN (是否已读)
- created_at: TIMESTAMP
- updated_at: TIMESTAMP
```

#### 3. get_or_create_conversation 函数
```sql
功能：
- 查找两个用户之间的现有会话
- 如果不存在，创建新会话
- 确保 participant1_id < participant2_id（规范化）
- 返回 conversation_id

用法：
SELECT get_or_create_conversation('user1-uuid', 'user2-uuid');
```

---

## 🔔 实时通知系统

### 实时功能说明

#### 1. RealtimeService.swift
负责：
- 会话内实时消息（聊天界面）
- 会话列表更新

#### 2. RealtimeCenter.swift
负责：
- 全局新消息通知
- 全局新通知提醒
- 未读计数更新

#### 3. UnreadCenter.swift
负责：
- 维护全局未读计数
- 在 TabBar 显示红点

### 实时订阅流程

```
用户登录
  ↓
AuthService.checkSession()
  ↓
RealtimeService.connect(userId)  // 私信实时
RealtimeCenter.connect(userId)   // 通知实时
  ↓
订阅 Supabase Realtime 频道
  ↓
收到新消息/通知 → 更新 UI
```

### 如何使用实时功能

在聊天界面订阅：
```swift
.task {
    await realtimeService.subscribeToConversationMessages(conversationId: conversationId) { message in
        // 收到新消息，更新 UI
        messages.append(message)
    }
}
```

在会话列表订阅：
```swift
.onReceive(realtimeService.$newMessage) { message in
    // 收到新消息，刷新列表
    if let msg = message {
        refreshConversations()
    }
}
```

---

## 🧪 测试清单

### 私信功能测试

- [ ] 点击用户的"私信"按钮能成功打开聊天界面
- [ ] 首次私信时自动创建会话
- [ ] 发送文字消息成功
- [ ] 消息按时间顺序显示
- [ ] 对方能看到我发送的消息（需要两个账号测试）
- [ ] 消息已读状态更新正确

### 实时功能测试

- [ ] 在聊天界面收到新消息时自动刷新
- [ ] 在会话列表收到新消息时显示提示
- [ ] TabBar 显示未读消息计数
- [ ] 点赞/评论时收到通知
- [ ] 被关注时收到通知
- [ ] 通知标记已读后未读计数减少

---

## 🐛 常见问题排查

### 问题1：仍然报找不到函数

**检查**：
```sql
SELECT proname FROM pg_proc WHERE proname = 'get_or_create_conversation';
```

**解决**：
如果返回空，说明迁移脚本没有执行成功。重新执行 `EXECUTE_THIS_MIGRATION.sql`。

### 问题2：私信发送失败

**检查**：
```sql
SELECT * FROM pg_policies WHERE tablename = 'messages';
```

**解决**：
确保 RLS 策略正确，允许用户插入自己发送的消息。

### 问题3：实时消息收不到

**检查 App 日志**：
```
✅ Successfully subscribed to messages channel
```

**解决**：
1. 确保在 Supabase Dashboard → Database → Replication 中启用了 `messages` 和 `conversations` 表的实时功能
2. 检查迁移脚本中的 Realtime 配置是否正确执行

### 问题4：未读计数不准确

**手动刷新**：
```swift
await RealtimeCenter.shared.refreshUnreadCounts(userId: userId)
```

**检查数据库**：
```sql
SELECT COUNT(*) FROM messages WHERE receiver_id = 'your-user-id' AND is_read = false;
SELECT COUNT(*) FROM notifications WHERE user_id = 'your-user-id' AND is_read = false;
```

---

## 📋 迁移脚本包含的内容

✅ **已包含**：
1. ✅ `conversations` 表创建
2. ✅ `messages` 表创建
3. ✅ 索引优化（提升查询性能）
4. ✅ RLS 策略（行级安全）
5. ✅ `get_or_create_conversation` 函数
6. ✅ `update_conversation_last_message` 函数和触发器
7. ✅ Realtime 订阅配置
8. ✅ 验证检查脚本

---

## 🎉 完成后的效果

### 私信功能
- ✅ 用户可以点击"私信"按钮打开聊天
- ✅ 支持发送文字消息
- ✅ 消息实时接收
- ✅ 会话列表按最后消息时间排序
- ✅ 显示未读消息计数

### 实时通知
- ✅ 收到点赞、评论、关注通知
- ✅ TabBar 显示通知红点
- ✅ 通知页面实时更新
- ✅ 标记已读功能

---

## 📞 需要帮助？

如果遇到问题：

1. **检查后台日志**
   - Xcode Console 中搜索 "❌" 或 "error"
   - 查看具体的错误信息

2. **检查 Supabase 日志**
   - Supabase Dashboard → Logs
   - 查看 API 请求和错误

3. **验证数据库状态**
   - 使用上面的 SQL 查询验证表和函数

4. **重新执行迁移**
   - 删除表：`DROP TABLE IF EXISTS messages, conversations CASCADE;`
   - 重新执行 `EXECUTE_THIS_MIGRATION.sql`

---

**祝修复顺利！** 🚀

如果一切正常，你应该能看到：
- ✅ 私信功能正常工作
- ✅ 实时消息接收
- ✅ 通知系统运行
- ✅ 未读计数准确
