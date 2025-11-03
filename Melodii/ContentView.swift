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

    @State private var selectedTab = 0
    @Environment(\.scenePhase) private var scenePhase

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
}

#Preview {
    ContentView()
        .modelContainer(for: [User.self, Post.self], inMemory: true)
}
