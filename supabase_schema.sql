-- ============================================
-- Melodii - Supabase数据库架构
-- ============================================

-- 启用必要的扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ============================================
-- 表结构
-- ============================================

-- 用户表
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    apple_user_id TEXT UNIQUE,
    nickname TEXT NOT NULL,
    avatar_url TEXT,
    bio TEXT,
    birthday TIMESTAMP WITH TIME ZONE,
    interests TEXT[] DEFAULT '{}',
    is_onboarding_completed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 帖子表
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT,
    media_urls TEXT[] DEFAULT '{}',
    topics TEXT[] DEFAULT '{}',
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    collect_count INTEGER DEFAULT 0,
    status TEXT DEFAULT 'published' CHECK (status IN ('draft', 'published', 'reviewing', 'rejected', 'deleted')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 评论表
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    like_count INTEGER DEFAULT 0,
    reply_to_id UUID REFERENCES comments(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 点赞表
CREATE TABLE likes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, post_id),
    UNIQUE(user_id, comment_id),
    CHECK (
        (post_id IS NOT NULL AND comment_id IS NULL) OR
        (post_id IS NULL AND comment_id IS NOT NULL)
    )
);

-- 收藏表
CREATE TABLE collections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

-- 通知表
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    actor_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('like', 'comment', 'reply', 'follow')),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 话题表
CREATE TABLE topics (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    post_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 举报表
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    reported_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    comment_id UUID REFERENCES comments(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    resolved_at TIMESTAMP WITH TIME ZONE
);

-- 私信表
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ============================================
-- 索引
-- ============================================

CREATE INDEX idx_posts_author_id ON posts(author_id);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_topics ON posts USING GIN(topics);

CREATE INDEX idx_comments_post_id ON comments(post_id);
CREATE INDEX idx_comments_author_id ON comments(author_id);
CREATE INDEX idx_comments_reply_to_id ON comments(reply_to_id);

CREATE INDEX idx_likes_user_id ON likes(user_id);
CREATE INDEX idx_likes_post_id ON likes(post_id);
CREATE INDEX idx_likes_comment_id ON likes(comment_id);

CREATE INDEX idx_collections_user_id ON collections(user_id);
CREATE INDEX idx_collections_post_id ON collections(post_id);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_is_read ON notifications(is_read);

CREATE INDEX idx_reports_status ON reports(status);

CREATE INDEX idx_messages_sender_id ON messages(sender_id);
CREATE INDEX idx_messages_receiver_id ON messages(receiver_id);

-- ============================================
-- 数据库函数
-- ============================================

-- 增加帖子点赞数
CREATE OR REPLACE FUNCTION increment_post_like_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET like_count = like_count + 1 WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 减少帖子点赞数
CREATE OR REPLACE FUNCTION decrement_post_like_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 增加帖子评论数
CREATE OR REPLACE FUNCTION increment_post_comment_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET comment_count = comment_count + 1 WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 减少帖子评论数
CREATE OR REPLACE FUNCTION decrement_post_comment_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 增加帖子收藏数
CREATE OR REPLACE FUNCTION increment_post_collect_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET collect_count = collect_count + 1 WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 减少帖子收藏数
CREATE OR REPLACE FUNCTION decrement_post_collect_count(post_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE posts SET collect_count = GREATEST(collect_count - 1, 0) WHERE id = post_id;
END;
$$ LANGUAGE plpgsql;

-- 增加评论点赞数
CREATE OR REPLACE FUNCTION increment_comment_like_count(comment_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE comments SET like_count = like_count + 1 WHERE id = comment_id;
END;
$$ LANGUAGE plpgsql;

-- 减少评论点赞数
CREATE OR REPLACE FUNCTION decrement_comment_like_count(comment_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE comments SET like_count = GREATEST(like_count - 1, 0) WHERE id = comment_id;
END;
$$ LANGUAGE plpgsql;

-- 更新话题帖子数
CREATE OR REPLACE FUNCTION update_topic_post_counts()
RETURNS void AS $$
BEGIN
    -- 先清零所有话题计数
    UPDATE topics SET post_count = 0;

    -- 重新计算每个话题的帖子数
    UPDATE topics t
    SET post_count = (
        SELECT COUNT(*)
        FROM posts p, unnest(p.topics) AS topic
        WHERE topic = t.name AND p.status = 'published'
    );
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- 触发器
-- ============================================

-- 自动更新updated_at字段
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_posts_updated_at BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_comments_updated_at BEFORE UPDATE ON comments
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- Row Level Security (RLS)
-- ============================================

-- 启用RLS
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE comments ENABLE ROW LEVEL SECURITY;
ALTER TABLE likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE collections ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE topics ENABLE ROW LEVEL SECURITY;
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Users表策略
CREATE POLICY "用户可以查看所有用户信息" ON users FOR SELECT USING (true);
CREATE POLICY "用户可以插入自己的信息" ON users FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "用户只能更新自己的信息" ON users FOR UPDATE USING (auth.uid() = id);

-- Posts表策略
CREATE POLICY "所有人可以查看已发布的帖子" ON posts FOR SELECT USING (status = 'published' OR author_id = auth.uid());
CREATE POLICY "认证用户可以创建帖子" ON posts FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND author_id = auth.uid());
CREATE POLICY "作者可以更新自己的帖子" ON posts FOR UPDATE USING (author_id = auth.uid());
CREATE POLICY "作者可以删除自己的帖子" ON posts FOR DELETE USING (author_id = auth.uid());

-- Comments表策略
CREATE POLICY "所有人可以查看评论" ON comments FOR SELECT USING (true);
CREATE POLICY "认证用户可以创建评论" ON comments FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND author_id = auth.uid());
CREATE POLICY "作者可以删除自己的评论" ON comments FOR DELETE USING (author_id = auth.uid());

-- Likes表策略
CREATE POLICY "用户可以查看所有点赞" ON likes FOR SELECT USING (true);
CREATE POLICY "认证用户可以点赞" ON likes FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());
CREATE POLICY "用户只能删除自己的点赞" ON likes FOR DELETE USING (user_id = auth.uid());

-- Collections表策略
CREATE POLICY "用户可以查看自己的收藏" ON collections FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "认证用户可以收藏" ON collections FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND user_id = auth.uid());
CREATE POLICY "用户只能删除自己的收藏" ON collections FOR DELETE USING (user_id = auth.uid());

-- Notifications表策略
CREATE POLICY "用户只能查看自己的通知" ON notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "认证用户可以创建通知" ON notifications FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "用户只能更新自己的通知" ON notifications FOR UPDATE USING (user_id = auth.uid());

-- Topics表策略
CREATE POLICY "所有人可以查看话题" ON topics FOR SELECT USING (true);
CREATE POLICY "认证用户可以创建话题" ON topics FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Reports表策略
CREATE POLICY "用户可以查看自己的举报" ON reports FOR SELECT USING (reporter_id = auth.uid());
CREATE POLICY "认证用户可以举报" ON reports FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND reporter_id = auth.uid());

-- Messages表策略
CREATE POLICY "用户可以查看自己的私信" ON messages FOR SELECT USING (sender_id = auth.uid() OR receiver_id = auth.uid());
CREATE POLICY "认证用户可以发送私信" ON messages FOR INSERT WITH CHECK (auth.uid() IS NOT NULL AND sender_id = auth.uid());
CREATE POLICY "用户可以删除自己发送的私信" ON messages FOR DELETE USING (sender_id = auth.uid());

-- ============================================
-- 初始数据
-- ============================================

-- 插入一些热门话题
INSERT INTO topics (name, description) VALUES
    ('日常', '分享生活中的日常点滴'),
    ('摄影', '用镜头记录美好瞬间'),
    ('美食', '分享美食心得和探店体验'),
    ('旅行', '记录旅途中的风景和故事'),
    ('音乐', '分享音乐心情和推荐'),
    ('运动', '健身、跑步等运动记录'),
    ('读书', '读书笔记和书籍推荐'),
    ('工作', '职场经验和工作感悟'),
    ('学习', '学习心得和知识分享'),
    ('宠物', '晒宠物的日常瞬间');

-- ============================================
-- 存储桶配置（需要在Supabase控制台创建）
-- ============================================

-- 创建media存储桶用于存储图片
-- 1. 在Supabase控制台的Storage部分创建名为"media"的bucket
-- 2. 设置为Public bucket（公开访问）
-- 3. 配置文件大小限制（建议10MB）
-- 4. 配置允许的文件类型：image/jpeg, image/png, image/gif, image/webp

-- ============================================
-- 完成
-- ============================================

-- 数据库架构创建完成！
-- 下一步：
-- 1. 在Supabase控制台执行此SQL脚本
-- 2. 在Storage部分创建"media"存储桶
-- 3. 在Authentication设置中配置Apple登录
-- 4. 复制项目URL和anon key到iOS应用的SupabaseConfig.swift
