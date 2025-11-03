# Melodii - 项目配置指南

这份文档将指导您完成Melodii项目的完整配置，包括Xcode项目设置、Supabase后端配置和Apple登录集成。

## 目录

1. [Xcode项目配置](#1-xcode项目配置)
2. [Supabase后端配置](#2-supabase后端配置)
3. [Apple登录配置](#3-apple登录配置)
4. [运行和测试](#4-运行和测试)
5. [故障排除](#5-故障排除)

---

## 1. Xcode项目配置

### 1.1 添加Supabase SDK

1. 在Xcode中打开 `Melodii.xcodeproj`
2. 点击项目导航栏中的项目名称（Melodii）
3. 选择 "Package Dependencies" 标签
4. 点击 "+" 按钮添加包依赖
5. 在搜索框中输入：`https://github.com/supabase-community/supabase-swift`
6. 选择最新版本（建议 >= 2.0.0）
7. 点击 "Add Package"
8. 在弹出的对话框中，确保勾选以下库：
   - `Supabase`
   - `Auth`
   - `PostgREST`
   - `Storage`
   - `Realtime`
9. 点击 "Add Package"

### 1.2 添加新创建的文件到项目

确保以下文件已添加到Xcode项目中：

**Models & Configuration:**
- `Models.swift`
- `SupabaseConfig.swift`

**Services:**
- `Services/SupabaseService.swift`
- `Services/AuthService.swift`
- `Services/StorageService.swift`

**Views:**
- `CreateView.swift`
- `ProfileView.swift`

**添加文件步骤：**
1. 在Xcode中，右键点击 `Melodii` 文件夹
2. 选择 "Add Files to Melodii..."
3. 导航到项目目录，选择上述文件
4. 确保勾选 "Copy items if needed" 和 "Add to targets: Melodii"
5. 点击 "Add"

### 1.3 配置Sign in with Apple

1. 在Xcode项目设置中，选择 "Signing & Capabilities"
2. 点击 "+ Capability" 按钮
3. 搜索并添加 "Sign in with Apple"
4. 确保选择了正确的Team和Bundle Identifier

### 1.4 更新App配置

编辑 `MelodiiApp.swift`，更新Schema为：

```swift
let schema = Schema([
    User.self,
    Post.self,
    Comment.self
])
```

---

## 2. Supabase后端配置

### 2.1 创建Supabase项目

1. 访问 [Supabase官网](https://supabase.com)
2. 注册/登录账号
3. 点击 "New Project"
4. 填写项目信息：
   - **Name**: Melodii（或您喜欢的名称）
   - **Database Password**: 设置一个强密码（请保存好）
   - **Region**: 选择离您最近的区域（建议选择Asia）
5. 点击 "Create new project"
6. 等待项目创建完成（约2-3分钟）

### 2.2 执行数据库脚本

1. 在Supabase项目仪表板中，点击左侧菜单的 "SQL Editor"
2. 点击 "New query" 创建新查询
3. 复制 `supabase_schema.sql` 文件的全部内容
4. 粘贴到SQL编辑器中
5. 点击右下角的 "Run" 按钮执行脚本
6. 确认所有表和函数创建成功（无错误提示）

### 2.3 创建Storage存储桶

1. 在左侧菜单中点击 "Storage"
2. 点击 "Create a new bucket"
3. 填写信息：
   - **Name**: `media`
   - **Public bucket**: 勾选（公开访问）
4. 点击 "Create bucket"

**配置存储桶策略：**
1. 点击刚创建的 `media` 存储桶
2. 点击 "Policies" 标签
3. 点击 "New Policy"
4. 选择 "For full customization" 创建自定义策略

**插入策略（允许认证用户上传）：**
- Policy name: `认证用户可以上传`
- Target roles: `authenticated`
- Policy definition:
```sql
(bucket_id = 'media'::text) AND (auth.uid() IS NOT NULL)
```

**选择策略（所有人可以查看）：**
- Policy name: `所有人可以查看`
- Target roles: `public`, `authenticated`
- Policy definition:
```sql
bucket_id = 'media'::text
```

**删除策略（用户只能删除自己的文件）：**
- Policy name: `用户删除自己的文件`
- Target roles: `authenticated`
- Policy definition:
```sql
(bucket_id = 'media'::text) AND ((storage.foldername(name))[1] = auth.uid()::text)
```

### 2.4 获取API密钥

1. 在左侧菜单点击 "Settings"（设置图标）
2. 点击 "API"
3. 复制以下信息：
   - **Project URL**（项目URL）
   - **anon public**（匿名公钥）

### 2.5 配置iOS应用

打开 `Melodii/SupabaseConfig.swift`，替换配置：

```swift
enum SupabaseConfig {
    static let url = "YOUR_SUPABASE_URL" // 粘贴您的Project URL
    static let anonKey = "YOUR_SUPABASE_ANON_KEY" // 粘贴您的anon public key

    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: URL(string: url)!,
            supabaseKey: anonKey
        )
    }()
}
```

---

## 3. Apple登录配置

### 3.1 Apple Developer配置

1. 访问 [Apple Developer](https://developer.apple.com)
2. 登录您的开发者账号
3. 进入 "Certificates, Identifiers & Profiles"
4. 选择 "Identifiers"，找到您的App ID
5. 确保 "Sign in with Apple" 已启用
6. 如果没有，点击编辑，勾选 "Sign in with Apple"，保存

### 3.2 在Supabase中配置Apple OAuth

1. 在Supabase仪表板左侧菜单，点击 "Authentication"
2. 点击 "Providers" 标签
3. 找到 "Apple" 提供商，点击配置
4. 勾选 "Enable Sign in with Apple"
5. 填写配置信息（这需要Apple Developer的额外配置）：
   - **Services ID**: 您的App Bundle ID
   - **Authorized Client IDs**: 您的App Bundle ID
   - **私钥**: 从Apple Developer下载的密钥文件

**获取Apple私钥：**
1. 在Apple Developer，进入 "Keys"
2. 点击 "+" 创建新密钥
3. 勾选 "Sign in with Apple"
4. 点击 "Configure"，选择您的Primary App ID
5. 保存并下载密钥文件（.p8文件）
6. 记录 Key ID 和 Team ID

6. 在Supabase中填写：
   - **Team ID**: 您的Apple Team ID（10位字符）
   - **Key ID**: 刚创建的密钥的ID
   - **Private Key**: 打开.p8文件，复制全部内容（包括BEGIN和END行）

7. 点击 "Save"

### 3.3 配置回调URL（可选）

如果使用Universal Links或深链接：
1. 在Supabase Authentication > URL Configuration
2. 添加您的应用回调URL
3. 格式：`melodii://auth/callback`（根据您的URL Scheme）

---

## 4. 运行和测试

### 4.1 首次运行

1. 在Xcode中选择模拟器或真机
2. 按 `Cmd + B` 构建项目
3. 确保没有编译错误
4. 按 `Cmd + R` 运行应用

### 4.2 测试功能清单

**P0核心功能测试：**

- [ ] **Apple登录**
  - 点击"我的"标签
  - 点击"使用Apple登录"
  - 完成Apple ID验证
  - 检查是否成功登录并显示用户信息

- [ ] **发现页**
  - 查看帖子列表
  - 点击"示例数据"插入测试数据
  - 滚动查看帖子

- [ ] **发帖功能**
  - 点击"发帖"标签
  - 输入文字内容
  - 选择图片（可选）
  - 添加话题标签
  - 点击"发布"
  - 检查是否成功发布

- [ ] **点赞功能**
  - 在帖子详情页点击点赞
  - 检查点赞数是否增加
  - 再次点击取消点赞

- [ ] **评论功能**
  - 进入帖子详情
  - 输入评论内容
  - 发送评论
  - 检查评论是否显示

- [ ] **个人页**
  - 查看个人信息
  - 查看"我的帖子"列表
  - 编辑资料（待实现）

- [ ] **通知**
  - 其他用户点赞/评论后
  - 检查是否收到通知

### 4.3 常见测试场景

1. **新用户注册流程**
   - 首次使用Apple登录
   - 创建第一条帖子
   - 浏览发现页

2. **内容创作流程**
   - 发布纯文字帖子
   - 发布图文混合帖子
   - 添加多个话题标签

3. **社交互动流程**
   - 点赞多个帖子
   - 评论帖子
   - 收藏感兴趣的内容

---

## 5. 故障排除

### 5.1 编译错误

**问题**: `Cannot find 'Supabase' in scope`
- **解决**: 确保已通过SPM添加Supabase包，并在项目中链接

**问题**: `Type 'User' has no member 'initials'`
- **解决**: 确保 `Models.swift` 中的User类包含initials计算属性

### 5.2 运行时错误

**问题**: Apple登录失败
- **检查**: Sign in with Apple capability是否已添加
- **检查**: Bundle ID是否在Apple Developer中配置正确
- **检查**: Supabase中的Apple OAuth配置是否正确

**问题**: 数据库操作失败（401 Unauthorized）
- **检查**: SupabaseConfig中的URL和Key是否正确
- **检查**: RLS策略是否正确配置
- **检查**: 用户是否已登录（某些操作需要认证）

**问题**: 图片上传失败
- **检查**: Storage存储桶"media"是否已创建
- **检查**: 存储桶策略是否允许上传
- **检查**: 图片大小是否超过限制

**问题**: 评论/点赞计数不更新
- **检查**: SQL脚本中的数据库函数是否执行成功
- **检查**: 在Supabase SQL Editor中手动执行函数测试

### 5.3 调试技巧

1. **查看Supabase日志**
   - 在Supabase仪表板，点击"Logs"
   - 查看API请求和错误信息

2. **使用Xcode调试**
   ```swift
   // 在关键位置添加断点和打印
   do {
       let posts = try await supabaseService.fetchPosts()
       print("✅ 获取到 \(posts.count) 条帖子")
   } catch {
       print("❌ 获取帖子失败: \(error)")
   }
   ```

3. **测试数据库连接**
   - 在Supabase SQL Editor中执行简单查询
   ```sql
   SELECT * FROM users LIMIT 5;
   ```

---

## 下一步开发建议

### P0功能完善（当前sprint）

1. **评论功能增强**
   - 回复评论
   - 评论的点赞

2. **通知中心**
   - 显示未读通知数
   - 通知详情页
   - 标记已读

3. **基础审核/举报**
   - 举报按钮
   - 举报理由选择
   - 内容审核队列（管理端）

### P1功能（下一sprint）

1. **话题系统**
   - 话题详情页
   - 话题订阅
   - 热门话题榜

2. **搜索功能**
   - 搜索帖子
   - 搜索用户
   - 搜索话题

3. **收藏和草稿**
   - 收藏列表页实现
   - 草稿箱功能
   - 草稿自动保存

4. **私信系统**
   - 会话列表
   - 聊天界面
   - 消息推送

### 技术优化建议

1. **性能优化**
   - 图片懒加载
   - 列表分页
   - 缓存策略

2. **用户体验**
   - 加载状态
   - 错误提示优化
   - 空状态页面

3. **安全性**
   - 内容过滤
   - 敏感词检测
   - 频率限制

---

## 资源链接

- [Supabase文档](https://supabase.com/docs)
- [Supabase Swift SDK](https://github.com/supabase-community/supabase-swift)
- [Apple Sign In文档](https://developer.apple.com/sign-in-with-apple/)
- [SwiftUI文档](https://developer.apple.com/documentation/swiftui/)

---

**需要帮助？**
如遇到问题，请检查：
1. Supabase项目状态
2. Xcode编译日志
3. 设备/模拟器日志
4. 网络连接状态

祝您开发顺利！🎉
