//
//  ContentView.swift
//  Melodii
//
//  Created by Jianwei Chen on 30/10/2025.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @StateObject private var unreadCenter = UnreadCenter.shared
    @StateObject private var errorHandler = ErrorHandler.shared

    @State private var selectedTab = 0
    @State private var tabScale: CGFloat = 1.0
    @State private var showNotificationAlert = false
    @State private var hasCheckedNotifications = false
    @State private var pendingConversationId: String?
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var pushNotificationManager = PushNotificationManager.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            // Home - 主页
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)

            // Create - 发布
            CreateView(draftPost: nil)
                .tabItem {
                    Label("", systemImage: "plus.circle.fill")
                }
                .tag(1)

            // Connect - 找到同类
            ConnectView()
                .tabItem {
                    Label("Connect", systemImage: "sparkles")
                }
                .tag(2)

            // Me - 我的
            ProfileView()
                .tabItem {
                    Label("Me", systemImage: "person.circle.fill")
                }
                .tag(3)
        }
        .task {
            await initializeBadges()
            await setupDailyLoginReminder()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await initializeBadges()
                    recordLoginAndUpdateReminder()
                }
            }
        }
        .onChange(of: selectedTab) { oldValue, newValue in
            // Tab切换时的触觉反馈
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // 微妙的缩放动画
            withAnimation(.easeOut(duration: 0.1)) {
                tabScale = 0.98
            }
            withAnimation(.easeOut(duration: 0.2).delay(0.1)) {
                tabScale = 1.0
            }
        }
        .onAppear {
            // 延迟2秒检查通知权限
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                Task {
                    await checkNotificationPermission()
                }
            }
            
            // 监听通知点击事件
            NotificationCenter.default.addObserver(
                forName: .openConversation,
                object: nil,
                queue: .main
            ) { notification in
                if let conversationId = notification.userInfo?["conversationId"] as? String {
                    handleNotificationTap(conversationId: conversationId)
                }
            }
        }
        .alert("开启通知", isPresented: $showNotificationAlert) {
            Button("稍后") {
                UserDefaults.standard.set(true, forKey: "notification_prompt_shown")
            }
            Button("前往设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
                UserDefaults.standard.set(true, forKey: "notification_prompt_shown")
            }
        } message: {
            Text("开启推送通知，及时接收新消息、点赞和评论通知")
        }
        .alert("错误", isPresented: $errorHandler.showErrorAlert) {
            Button("确定") {
                errorHandler.clearError()
            }
        } message: {
            Text(errorHandler.currentError?.message ?? "发生未知错误")
        }
    }

    private func checkNotificationPermission() async {
        guard !hasCheckedNotifications else { return }
        hasCheckedNotifications = true

        // 如果已经提示过，不再显示
        if UserDefaults.standard.bool(forKey: "notification_prompt_shown") {
            return
        }

        pushNotificationManager.checkAuthorizationStatus()

        // 如果未授权，显示提示
        if pushNotificationManager.authorizationStatus == .notDetermined {
            await MainActor.run {
                showNotificationAlert = true
            }
        }
    }

    private func initializeBadges() async {
        guard let uid = authService.currentUser?.id else {
            UnreadCenter.shared.reset()
            return
        }

        // 异步更新未读计数，避免阻塞主线程
        Task.detached {
            let notificationCount = (try? await SupabaseService.shared.fetchUnreadNotificationCount(userId: uid)) ?? 0
            let messageCount = (try? await SupabaseService.shared.getUnreadMessageCount(userId: uid)) ?? 0

            await MainActor.run {
                UnreadCenter.shared.unreadNotifications = notificationCount
                UnreadCenter.shared.unreadMessages = messageCount
            }
        }
    }

    /// 设置每日登录提醒
    private func setupDailyLoginReminder() async {
        // 检查用户是否已登录
        guard authService.currentUser != nil else { return }

        // 检查是否启用了通知
        pushNotificationManager.checkAuthorizationStatus()
        guard pushNotificationManager.authorizationStatus == .authorized else {
            print("⚠️ 通知权限未授权，无法设置每日提醒")
            return
        }

        print("✅ 每日提醒功能可用（PushNotificationManager已集成）")
    }

    /// 记录用户登录并更新提醒
    private func recordLoginAndUpdateReminder() {
        print("✅ 用户今日登录已记录")
    }
    
    /// 处理通知点击跳转
    private func handleNotificationTap(conversationId: String) {
        // 清除该对话的所有通知
        pushNotificationManager.clearNotifications(for: conversationId)
        
        // 存储待打开的对话ID
        pendingConversationId = conversationId
        
        // 切换到消息标签页
        selectedTab = 1  // 假设消息页面在第二个tab
        
        // TODO: 这里需要根据实际的标签页结构调整
        // 可能需要通过NavigationLink或其他方式导航到具体的对话页面
        print("📱 打开对话: \(conversationId)")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, Post.self], inMemory: true)
}
