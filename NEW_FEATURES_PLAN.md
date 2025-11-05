# 新功能实现方案

## 📋 需求清单

### 1. 多媒体帖子优化 📸
- [ ] 创作时选择封面图片
- [ ] 帖子显示所有图片/视频
- [ ] 点击查看完整媒体画廊

### 2. 帖子删除同步 🗑️
- [ ] 个人主页删除帖子
- [ ] 首页feed同步删除
- [ ] 实时更新

### 3. 未读消息徽章系统 🔴
- [ ] 准确显示未读数量
- [ ] 读取后自动清除
- [ ] 应用图标badge

### 4. 消息推送通知 📢
- [ ] 收到新消息时推送
- [ ] 显示发送者和内容
- [ ] 点击跳转到对话

---

## 实现方案

### 方案 1: 未读消息Badge系统 🔴

#### 当前状态
✅ 已有 `UnreadCenter` 管理未读计数
✅ 已有 `NotificationManager` 更新badge
✅ MainTabView 显示tab badge

#### 需要改进

**1. 在收到消息时更新计数**

文件：`RealtimeMessagingService.swift`

```swift
// 在收到新消息时
if let currentUserId = authService.currentUser?.id,
   message.receiverId == currentUserId,
   !message.isRead {
    // 增加未读计数
    UnreadCenter.shared.incrementMessages()

    // 更新应用badge
    NotificationManager.shared.updateBadge()
}
```

**2. 标记消息已读时减少计数**

文件：`ConversationView.swift`

```swift
private func markMessagesAsRead() {
    if let myId = authService.currentUser?.id {
        let unread = messages.filter { $0.receiverId == myId && !$0.isRead }

        for msg in unread {
            try? await supabaseService.markMessageAsRead(messageId: msg.id)
        }

        if !unread.isEmpty {
            UnreadCenter.shared.decrementMessages(unread.count)
            NotificationManager.shared.updateBadge()
        }
    }
}
```

**3. 应用启动时加载未读计数**

文件：`MainTabView.swift`

```swift
private func initializeBadges() async {
    guard let userId = authService.currentUser?.id else { return }

    do {
        // 获取未读消息数
        let unreadCount = try await supabaseService.fetchUnreadMessageCount(userId: userId)

        await MainActor.run {
            unreadCenter.unreadMessages = unreadCount
        }

        // 更新应用badge
        await NotificationManager.shared.updateBadge()
    } catch {
        print("获取未读计数失败: \(error)")
    }
}
```

**4. 在SupabaseService中添加获取未读消息数的方法**

```swift
func fetchUnreadMessageCount(userId: String) async throws -> Int {
    let response: [Message] = try await client
        .from("messages")
        .select()
        .eq("receiver_id", value: userId)
        .eq("is_read", value: false)
        .execute()
        .value

    return response.count
}
```

---

### 方案 2: 推送通知 📢

#### 1. 发送新消息通知

文件：`ConversationView.swift` 或 `RealtimeMessagingService.swift`

```swift
private func sendPushNotification(for message: Message, to recipientId: String) async {
    guard let sender = authService.currentUser else { return }

    let content = message.messageType == .text
        ? message.content
        : "[图片]"  // 或 [语音]

    await NotificationManager.shared.sendMessageNotification(
        to: recipientId,
        from: sender.nickname,
        message: content,
        conversationId: message.conversationId
    )
}
```

#### 2. 后端触发器（可选）

在Supabase中创建触发器，当插入新消息时自动发送推送：

```sql
CREATE OR REPLACE FUNCTION notify_new_message()
RETURNS TRIGGER AS $$
BEGIN
    -- 调用云函数或webhook发送推送通知
    PERFORM http_post(
        'https://your-notification-server.com/send',
        json_build_object(
            'receiver_id', NEW.receiver_id,
            'sender_id', NEW.sender_id,
            'message', NEW.content,
            'conversation_id', NEW.conversation_id
        )::text
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_new_message
AFTER INSERT ON messages
FOR EACH ROW
EXECUTE FUNCTION notify_new_message();
```

#### 3. 处理通知点击

文件：`MelodiiApp.swift`

```swift
func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
) {
    let userInfo = response.notification.request.content.userInfo

    if let conversationId = userInfo["conversationId"] as? String {
        // 跳转到对话页面
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenConversation"),
            object: nil,
            userInfo: ["conversationId": conversationId]
        )
    }

    completionHandler()
}
```

---

### 方案 3: 帖子删除同步 🗑️

#### 当前问题
删除帖子后，首页feed可能仍然显示该帖子（缓存问题）

#### 解决方案

**方法 1: 使用NotificationCenter广播**

```swift
// 在删除帖子后
extension Notification.Name {
    static let postDeleted = Notification.Name("PostDeleted")
}

// ProfileView 删除帖子
private func deletePost(_ post: Post) async {
    do {
        try await supabaseService.deletePost(postId: post.id)

        // 广播删除事件
        NotificationCenter.default.post(
            name: .postDeleted,
            object: nil,
            userInfo: ["postId": post.id]
        )

        // 从本地列表移除
        posts.removeAll { $0.id == post.id }
    } catch {
        print("删除失败: \(error)")
    }
}

// DiscoverView 监听删除事件
.onReceive(NotificationCenter.default.publisher(for: .postDeleted)) { notification in
    if let postId = notification.userInfo?["postId"] as? String {
        // 从feed中移除
        recommendedState.items.removeAll { $0.id == postId }
        followingState.items.removeAll { $0.id == postId }
    }
}
```

**方法 2: 使用Published属性 + ObservableObject**

创建PostManager来管理全局帖子状态：

```swift
@MainActor
class PostManager: ObservableObject {
    static let shared = PostManager()

    @Published var deletedPostIds: Set<String> = []

    func markAsDeleted(_ postId: String) {
        deletedPostIds.insert(postId)
    }
}

// 在DiscoverView中过滤已删除的帖子
var visiblePosts: [Post] {
    currentPosts.filter { !PostManager.shared.deletedPostIds.contains($0.id) }
}
```

---

### 方案 4: 多媒体帖子封面选择 📸

#### 1. 创作时选择封面

文件：`CreateView.swift`

**添加封面选择状态：**

```swift
@State private var selectedCoverIndex: Int = 0  // 封面索引
@State private var showCoverPicker = false

// 在媒体网格中添加封面选择
ForEach(Array(selectedMedia.enumerated()), id: \.offset) { index, item in
    ZStack(alignment: .topLeading) {
        // 媒体预览
        MediaThumbnail(item: item)

        // 封面标记
        if index == selectedCoverIndex {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                Text("封面")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .padding(4)
            .background(.ultraThinMaterial)
            .cornerRadius(4)
            .padding(6)
        }
    }
    .onTapGesture {
        // 点击设置为封面
        withAnimation {
            selectedCoverIndex = index
        }
    }
}
```

**提交时保存封面索引：**

```swift
// 修改Post模型添加coverIndex字段
// 或者将封面URL放在mediaURLs数组的第一位

// 提交前重新排序
var orderedMediaURLs = uploadedMediaURLs
if selectedCoverIndex > 0 {
    let cover = orderedMediaURLs.remove(at: selectedCoverIndex)
    orderedMediaURLs.insert(cover, at: 0)
}
```

#### 2. 帖子显示封面

Feed中只显示第一张图片作为封面：

```swift
// DiscoverView 或 PostCard
if let firstMedia = post.mediaURLs.first {
    AsyncImage(url: URL(string: firstMedia)) { image in
        image
            .resizable()
            .scaledToFill()
            .frame(height: 300)
            .clipped()
    } placeholder: {
        Rectangle()
            .fill(Color(.systemGray6))
            .overlay(ProgressView())
    }

    // 显示媒体数量
    if post.mediaURLs.count > 1 {
        HStack {
            Image(systemName: "photo.stack")
            Text("\(post.mediaURLs.count)")
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}
```

#### 3. 点击查看所有媒体

```swift
@State private var showMediaGallery = false
@State private var selectedPost: Post?

// 点击帖子
.onTapGesture {
    selectedPost = post
    showMediaGallery = true
}

// 全屏媒体查看器
.sheet(isPresented: $showMediaGallery) {
    if let post = selectedPost {
        FullscreenMediaViewer(
            urls: post.mediaURLs,
            isPresented: $showMediaGallery,
            index: 0
        )
    }
}
```

---

## 数据库修改

### 添加覆盖索引（可选）

```sql
ALTER TABLE posts
ADD COLUMN cover_index INTEGER DEFAULT 0;

COMMENT ON COLUMN posts.cover_index IS '封面媒体在media_urls数组中的索引';
```

### 添加未读消息查询索引

```sql
CREATE INDEX IF NOT EXISTS idx_messages_unread
ON messages(receiver_id, is_read)
WHERE is_read = false;
```

---

## 实现优先级

### P0 (立即实现)
1. ✅ 未读消息badge系统
2. ✅ 消息已读后清除badge

### P1 (本周实现)
3. ✅ 推送通知
4. ✅ 帖子删除同步

### P2 (下周实现)
5. ⭕ 多媒体封面选择
6. ⭕ 媒体画廊查看器

---

## 测试清单

### 未读消息Badge
- [ ] 收到新消息时，应用图标显示数字
- [ ] 打开对话后，数字减少
- [ ] 全部已读后，数字消失
- [ ] 多个对话的未读数累加

### 推送通知
- [ ] 应用在后台时收到通知
- [ ] 通知内容显示发送者和消息
- [ ] 点击通知打开对应对话
- [ ] 在对话页面时不发送通知

### 帖子删除
- [ ] 个人主页删除帖子
- [ ] 首页feed同步移除
- [ ] 其他页面（PostDetail等）也移除

### 多媒体帖子
- [ ] 创作时可选择封面
- [ ] Feed显示封面和数量
- [ ] 点击查看所有媒体
- [ ] 左右滑动浏览

---

## 需要的代码文件

### 新增
- `PostManager.swift` - 全局帖子管理器

### 修改
- `UnreadCenter.swift` - 增强未读管理
- `RealtimeMessagingService.swift` - 添加badge更新
- `ConversationView.swift` - 标记已读
- `SupabaseService.swift` - 添加未读查询
- `CreateView.swift` - 添加封面选择
- `DiscoverView.swift` - 监听删除事件
- `Models.swift` - 添加coverIndex字段（可选）

---

## 预计工作量

| 功能 | 时间 | 难度 |
|------|------|------|
| 未读Badge系统 | 2小时 | 🟢 低 |
| 推送通知 | 3小时 | 🟡 中 |
| 帖子删除同步 | 1小时 | 🟢 低 |
| 多媒体封面 | 4小时 | 🟡 中 |
| **总计** | **10小时** | |

---

由于任务较多，建议分阶段实现。我现在先实现**未读消息badge系统**，这是最紧急的功能。
