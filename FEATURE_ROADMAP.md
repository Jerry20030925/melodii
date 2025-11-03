# Melodii 功能开发路线图

## ✅ 已完成功能
- [x] 温柔 MVP UI 设计
- [x] 情绪标签系统
- [x] 匿名发布
- [x] 城市标记
- [x] Connect 找同类页面
- [x] 无压力 Feed 设计
- [x] 下拉刷新功能

## 🚀 待开发功能（按优先级排序）

### 阶段 1：核心社交功能（高优先级）

#### 1.1 关注功能增强
- [ ] 在主页添加 "Following" Tab
  - 显示仅关注用户的帖子
  - 切换 "推荐" 和 "关注" 两个 feed
- [ ] 优化关注/取消关注流程

#### 1.2 搜索功能
- [ ] 主页添加搜索按钮
- [ ] 搜索用户（通过 MID 或昵称）
- [ ] 搜索结果页面
- [ ] 搜索历史

#### 1.3 用户主页完善
- [ ] 点击头像进入用户主页
- [ ] 显示用户信息：
  - 头像
  - 昵称
  - MID（显著位置）
  - 个人简介
  - 兴趣标签
- [ ] 显示用户的帖子列表
- [ ] 关注/私信按钮

### 阶段 2：个人资料编辑（高优先级）

#### 2.1 头像功能
- [ ] 头像上传
- [ ] 头像裁剪
- [ ] 头像预览

#### 2.2 背景图功能
- [ ] 封面图片上传
- [ ] 封面图片裁剪
- [ ] 封面图片预览

#### 2.3 资料编辑
- [ ] 昵称修改
- [ ] 个人简介编辑
- [ ] 兴趣标签编辑
- [ ] 保存修改

### 阶段 3：帖子管理（中优先级）

#### 3.1 我的帖子
- [ ] 创建 "我的帖子" 页面
- [ ] 显示所有发布的帖子
- [ ] 帖子删除功能
- [ ] 帖子隐藏功能（仅自己可见）
- [ ] 帖子编辑功能

#### 3.2 帖子操作
- [ ] 删除确认弹窗
- [ ] 隐藏/显示切换
- [ ] 批量管理

### 阶段 4：私信系统（中优先级）

#### 4.1 私信基础功能
- [ ] 私信列表页面
- [ ] 对话页面
- [ ] 发送文字消息
- [ ] 发送图片
- [ ] 消息已读状态

#### 4.2 实时功能
- [ ] 实时接收消息（Supabase Realtime）
- [ ] 未读消息提示
- [ ] 消息推送通知

### 阶段 5：通知系统（中优先级）

#### 5.1 通知类型
- [ ] 点赞通知
- [ ] 评论通知
- [ ] 关注通知
- [ ] 私信通知

#### 5.2 通知中心
- [ ] 通知列表页面
- [ ] 未读标记
- [ ] 通知分类
- [ ] 清空已读

#### 5.3 实时推送
- [ ] Supabase Realtime 集成
- [ ] 本地通知
- [ ] 推送通知（可选）

---

## 📊 开发优先级说明

### 🔴 高优先级（P0）
1. 关注 Feed
2. 搜索功能
3. 用户主页查看
4. 个人资料编辑（头像、昵称、背景图）

### 🟡 中优先级（P1）
1. 我的帖子管理
2. 私信系统
3. 通知系统

### 🟢 低优先级（P2）
1. 帖子编辑
2. 批量管理
3. 高级搜索

---

## 🛠 技术实现要点

### 数据库更新需求

#### User 表需要新增字段：
```sql
ALTER TABLE users ADD COLUMN avatar_url text;
ALTER TABLE users ADD COLUMN cover_image_url text;
```

#### Posts 表需要新增字段：
```sql
ALTER TABLE posts ADD COLUMN is_hidden boolean DEFAULT false;
```

#### 新表需求：
```sql
-- 私信表
CREATE TABLE messages (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  sender_id uuid REFERENCES users(id),
  receiver_id uuid REFERENCES users(id),
  content text NOT NULL,
  media_urls text[],
  is_read boolean DEFAULT false,
  created_at timestamp DEFAULT now()
);

-- 通知表
CREATE TABLE notifications (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid REFERENCES users(id),
  type text NOT NULL, -- 'like', 'comment', 'follow', 'message'
  actor_id uuid REFERENCES users(id),
  post_id uuid REFERENCES posts(id),
  is_read boolean DEFAULT false,
  created_at timestamp DEFAULT now()
);
```

### 实时功能技术栈
- Supabase Realtime Channels
- Combine 框架处理实时数据流
- SwiftUI 自动更新 UI

---

## 📅 开发计划（建议）

### 第 1 周：核心社交功能
- Day 1-2: 关注 Feed
- Day 3-4: 搜索功能
- Day 5: 用户主页查看

### 第 2 周：个人资料
- Day 1-2: 头像上传
- Day 3-4: 背景图上传
- Day 5: 资料编辑

### 第 3 周：帖子管理
- Day 1-3: 我的帖子页面
- Day 4-5: 删除/隐藏功能

### 第 4 周：私信与通知
- Day 1-3: 私信系统
- Day 4-5: 通知系统

---

## 🎯 当前任务

我建议按以下顺序开始实现：

1. **关注 Feed** - 让用户可以看到关注的人的动态
2. **搜索功能** - 可以通过 MID 找到其他用户
3. **用户主页** - 点击头像查看对方资料
4. **个人资料编辑** - 上传头像、背景图，修改昵称

你想从哪个功能开始？我建议从 **关注 Feed** 开始，因为这是最核心的社交功能。
