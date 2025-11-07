import SwiftUI

struct MainTabView: View {
    @StateObject private var unreadCenter = UnreadCenter.shared
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("发现", systemImage: "sparkles") }

            ConversationsView()
                .tabItem { Label("消息", systemImage: "message") }
                .badge(unreadCenter.unreadMessages)

            NotificationsView()
                .tabItem { Label("通知", systemImage: "bell") }
                .badge(unreadCenter.unreadNotifications)
        }
        .task {
            await initializeBadges()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await initializeBadges() }
            }
        }
    }

    private func initializeBadges() async {
        guard let uid = authService.currentUser?.id else {
            UnreadCenter.shared.reset()
            return
        }

        // 获取未读计数
        UnreadCenter.shared.unreadNotifications = (try? await supabaseService.fetchUnreadNotificationCount(userId: uid)) ?? 0
        UnreadCenter.shared.unreadMessages = (try? await supabaseService.getUnreadMessageCount(userId: uid)) ?? 0

        print("✅ 未读消息初始化完成: 通知 \(UnreadCenter.shared.unreadNotifications), 消息 \(UnreadCenter.shared.unreadMessages)")
    }
}
