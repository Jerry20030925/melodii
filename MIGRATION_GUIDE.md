# Melodii 数据库迁移指南

## 最新迁移：添加帖子新字段

### 迁移内容
此迁移为 `posts` 表添加了以下三个新字段，以支持温柔 MVP UI 设计：

1. **mood_tags** (text[]) - 情绪标签数组
2. **city** (text) - 城市信息（可选）
3. **is_anonymous** (boolean) - 匿名发布标识

### 如何应用迁移

#### 方式 1: 使用 Supabase Dashboard（推荐）

1. 登录 [Supabase Dashboard](https://app.supabase.com)
2. 选择你的项目
3. 点击左侧菜单的 **SQL Editor**
4. 点击 **New query**
5. 复制 `supabase_migration_add_post_fields.sql` 的内容
6. 粘贴到 SQL 编辑器
7. 点击 **Run** 执行

#### 方式 2: 使用 Supabase CLI

```bash
# 确保你在项目根目录
cd /Users/jerry/Melodii

# 应用迁移
supabase db push --db-url "your-database-url" --file supabase_migration_add_post_fields.sql
```

#### 方式 3: 使用 psql

```bash
psql "your-database-connection-string" -f supabase_migration_add_post_fields.sql
```

### 验证迁移

迁移完成后，你应该在控制台看到：

```
NOTICE:  ✅ mood_tags 列添加成功
NOTICE:  ✅ city 列添加成功
NOTICE:  ✅ is_anonymous 列添加成功
```

你也可以在 Supabase Dashboard 的 Table Editor 中查看 `posts` 表，确认新列已添加。

### 如何回滚（如果需要）

⚠️ **警告：回滚将删除这些列及其所有数据！**

如果需要撤销此迁移：

1. 在 Supabase Dashboard 的 SQL Editor 中
2. 复制 `supabase_migration_rollback_post_fields.sql` 的内容
3. 执行脚本

### 测试新功能

迁移完成后，你可以：

1. 启动 Melodii 应用
2. 尝试发布新动态，选择情绪标签和城市
3. 测试匿名发布功能
4. 在主页查看带有情绪标签的帖子

### 现有数据处理

- 所有现有帖子的 `mood_tags` 将为空数组 `[]`
- 所有现有帖子的 `city` 将为 `NULL`
- 所有现有帖子的 `is_anonymous` 将为 `false`

这不会影响现有帖子的显示。

### 相关文件

- **迁移脚本**: `supabase_migration_add_post_fields.sql`
- **回滚脚本**: `supabase_migration_rollback_post_fields.sql`
- **数据模型**: `Melodii/Models.swift`
- **主页视图**: `Melodii/Views/HomeView.swift`
- **发布视图**: `Melodii/CreateView.swift`

### 需要帮助？

如果迁移过程中遇到问题：

1. 检查数据库连接
2. 确保有足够的权限
3. 查看 Supabase 日志
4. 尝试手动添加单个列进行测试

---

**迁移日期**: 2025-11-03
**版本**: v1.1.0
**功能**: 温柔 MVP UI 设计支持
