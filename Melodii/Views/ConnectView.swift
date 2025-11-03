//
//  ConnectView.swift
//  Melodii
//
//  探索与连接 - 发现新功能和新朋友
//

import SwiftUI

struct ConnectView: View {
    @ObservedObject private var authService = AuthService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 顶部特色功能卡片
                    featureSectionHeader

                    // 功能网格
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ],
                        spacing: 16
                    ) {
                        // 摇一摇发现
                        FeatureCard(
                            icon: "sparkles",
                            title: "摇一摇",
                            subtitle: "发现有趣的人",
                            gradient: [.blue, .purple],
                            destination: AnyView(ShakeDiscoveryView())
                        )

                        // 情绪日记
                        FeatureCard(
                            icon: "heart.text.square",
                            title: "情绪日记",
                            subtitle: "记录心情变化",
                            gradient: [.pink, .orange],
                            destination: AnyView(MoodTrackerView())
                        )

                        // 每日挑战
                        FeatureCard(
                            icon: "trophy",
                            title: "每日挑战",
                            subtitle: "赢取积分奖励",
                            gradient: [.orange, .red],
                            destination: AnyView(DailyChallengeView())
                        )

                        // 私信列表
                        FeatureCard(
                            icon: "bubble.left.and.bubble.right",
                            title: "私信",
                            subtitle: "查看所有对话",
                            gradient: [.green, .mint],
                            destination: AnyView(MessagesListView())
                        )
                    }

                    // 热门话题
                    trendingTopicsSection
                }
                .padding()
            }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Feature Section Header

    private var featureSectionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✨ 发现精彩")
                .font(.title2)
                .fontWeight(.bold)

            Text("探索独特功能，连接有趣的人")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Trending Topics

    private var trendingTopicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🔥 热门话题")
                .font(.headline)
                .fontWeight(.semibold)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(["音乐", "旅行", "美食", "摄影", "读书", "运动"], id: \.self) { topic in
                        Button {
                            // TODO: 跳转到话题页
                        } label: {
                            HStack(spacing: 6) {
                                Text("#\(topic)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text("•")
                                    .font(.caption)

                                Text("\(Int.random(in: 100...9999))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color(.systemGray6))
                            )
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let destination: AnyView

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 12) {
                // 图标
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)
                        .shadow(
                            color: gradient.first?.opacity(0.4) ?? .clear,
                            radius: 10,
                            x: 0,
                            y: 5
                        )

                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.white)
                }

                // 文字
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Messages List View (原来的对话列表)

private struct MessagesListView: View {
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var realtimeService = RealtimeService.shared

    @State private var conversations: [Conversation] = []
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if conversations.isEmpty {
                ContentUnavailableView(
                    "还没有对话",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("开始与其他用户聊天吧")
                )
            } else {
                conversationsList
            }
        }
        .navigationTitle("私信")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await loadConversations()
        }
        .task {
            await loadConversations()
        }
        .alert("提示", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var conversationsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(conversations) { conversation in
                    if let otherUser = conversation.getOtherUser(currentUserId: authService.currentUser?.id ?? "") {
                        NavigationLink {
                            ConversationView(conversation: conversation, otherUser: otherUser)
                        } label: {
                            ConnectConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)

                        Divider()
                            .padding(.leading, 88)
                    }
                }
            }
        }
    }

    // MARK: - Loading & Empty States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("加载中...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("还没有私信")
                    .font(.title3)
                    .fontWeight(.medium)

                Text("在首页或搜索中找到感兴趣的人\n点击\"私信\"开始对话")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Data Loading

    private func loadConversations() async {
        guard let userId = authService.currentUser?.id else {
            errorMessage = "请先登录"
            showError = true
            return
        }

        isLoading = true

        do {
            conversations = try await supabaseService.fetchConversations(userId: userId)
            print("✅ 加载了 \(conversations.count) 个会话")
        } catch {
            errorMessage = "加载会话失败: \(error.localizedDescription)"
            showError = true
            print("❌ 加载会话失败: \(error)")
        }

        isLoading = false
    }
}

// MARK: - Conversation Row

private struct ConnectConversationRow: View {
    let conversation: Conversation

    @ObservedObject private var authService = AuthService.shared

    var otherUser: User? {
        guard let myId = authService.currentUser?.id else { return nil }
        return conversation.getOtherUser(currentUserId: myId)
    }

    var body: some View {
        HStack(spacing: 16) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 56, height: 56)
                .overlay(
                    Text(otherUser?.initials ?? "?")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(otherUser?.nickname ?? "未知用户")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(formatTime(conversation.lastMessageAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 最后一条消息预览
                if let lastMsg = conversation.lastMessage {
                    Text(lastMsg.content)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("开始聊天...")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "昨天"
        } else if calendar.component(.weekOfYear, from: date) == calendar.component(.weekOfYear, from: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
    }
}

#Preview {
    ConnectView()
}
