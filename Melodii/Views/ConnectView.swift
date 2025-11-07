//
//  ConnectView.swift
//  Melodii
//
//  探索与连接 - 发现新功能和新朋友
//

import SwiftUI

struct ConnectView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    @State private var selectedFeatureIndex: Int?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // 顶部特色功能卡片
                    featureSectionHeader
                        .padding(.horizontal)

                    // 圆形功能卡片 - 水平滚动
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            // 摇一摇发现
                            CircularFeatureCard(
                                icon: "sparkles",
                                title: "摇一摇",
                                subtitle: "发现有趣的人",
                                gradient: [.blue, .purple],
                                destination: AnyView(ShakeDiscoveryView()),
                                isSelected: selectedFeatureIndex == 0
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeatureIndex = 0
                                }
                            }

                            // 情绪日记
                            CircularFeatureCard(
                                icon: "heart.text.square",
                                title: "情绪日记",
                                subtitle: "记录心情变化",
                                gradient: [.pink, .orange],
                                destination: AnyView(MoodTrackerView()),
                                isSelected: selectedFeatureIndex == 1
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeatureIndex = 1
                                }
                            }

                            // 每日挑战
                            CircularFeatureCard(
                                icon: "trophy",
                                title: "每日挑战",
                                subtitle: "赢取积分奖励",
                                gradient: [.orange, .red],
                                destination: AnyView(DailyChallengeView()),
                                isSelected: selectedFeatureIndex == 2
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeatureIndex = 2
                                }
                            }

                            // 私信列表
                            CircularFeatureCard(
                                icon: "bubble.left.and.bubble.right",
                                title: "私信",
                                subtitle: "查看所有对话",
                                gradient: [.green, .mint],
                                destination: AnyView(MessagesListView()),
                                isSelected: selectedFeatureIndex == 3
                            )
                            .onTapGesture {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedFeatureIndex = 3
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 8)

                    // 聊天列表
                    conversationsSection
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("探索")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Conversations Section

    @State private var conversations: [Conversation] = []
    @State private var isLoadingConversations = false

    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("💬 最近聊天")
                    .font(.title3)
                    .fontWeight(.bold)

                Spacer()

                NavigationLink {
                    MessagesListView()
                } label: {
                    Text("查看全部")
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
            }

            if isLoadingConversations {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else if conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("还没有对话")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    NavigationLink {
                        SearchView()
                    } label: {
                        Text("去发现新朋友")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6).opacity(0.5))
                )
            } else {
                VStack(spacing: 12) {
                    ForEach(conversations.prefix(5)) { conversation in
                        if let otherUser = conversation.getOtherUser(currentUserId: authService.currentUser?.id ?? "") {
                            NavigationLink {
                                ConversationView(conversation: conversation, otherUser: otherUser)
                            } label: {
                                CompactConversationRow(conversation: conversation, otherUser: otherUser)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .task {
            await loadConversations()
        }
    }

    private func loadConversations() async {
        guard let userId = authService.currentUser?.id else { return }

        isLoadingConversations = true

        do {
            let allConversations = try await supabaseService.fetchConversations(userId: userId)
            await MainActor.run {
                conversations = allConversations
            }
        } catch {
            print("❌ 加载会话失败: \(error)")
        }

        isLoadingConversations = false
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

}

// MARK: - Circular Feature Card

private struct CircularFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let gradient: [Color]
    let destination: AnyView
    let isSelected: Bool

    @State private var isPressed = false

    var body: some View {
        NavigationLink {
            destination
        } label: {
            VStack(spacing: 16) {
                // 大圆形图标
                ZStack {
                    // 外圈光晕效果
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient.map { $0.opacity(0.3) },
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .blur(radius: 10)
                        .opacity(isSelected ? 1 : 0.5)

                    // 主圆形
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 90, height: 90)
                        .shadow(
                            color: gradient.first?.opacity(0.5) ?? .clear,
                            radius: isPressed ? 5 : 15,
                            x: 0,
                            y: isPressed ? 2 : 8
                        )

                    // 图标
                    Image(systemName: icon)
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: isSelected)
                }
                .scaleEffect(isPressed ? 0.95 : (isSelected ? 1.05 : 1.0))
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)

                // 文字信息
                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(width: 100)
            }
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = true
                    }
                }
                .onEnded { _ in
                    withAnimation(.easeInOut(duration: 0.1)) {
                        isPressed = false
                    }
                }
        )
    }
}

// MARK: - Messages List View (原来的对话列表)

private struct MessagesListView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
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

// MARK: - Compact Conversation Row

private struct CompactConversationRow: View {
    let conversation: Conversation
    let otherUser: User

    var body: some View {
        HStack(spacing: 12) {
            // 头像
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(0.6), .pink.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
                .overlay(
                    Text(otherUser.initials)
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(otherUser.nickname)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Spacer()

                    Text(formatTime(conversation.lastMessageAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // 最后一条消息预览
                if let lastMsg = conversation.lastMessage {
                    Text(lastMsg.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("开始聊天...")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
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
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: date)
        }
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
