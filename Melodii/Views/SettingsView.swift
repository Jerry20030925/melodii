//
//  SettingsView.swift
//  Melodii
//
//  Complete settings page with theme and privacy options
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared

    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        NavigationStack {
            List {
                // 语言设置
                Section {
                    Picker(LocalizedStringKey("语言"), selection: $languageManager.currentLanguage) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.rawValue).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: languageManager.currentLanguage) { _, newValue in
                        languageManager.setLanguage(newValue)
                    }
                } header: {
                    Label(LocalizedStringKey("语言"), systemImage: "globe")
                }
                // 外观设置
                Section {
                    Picker(LocalizedStringKey("主题模式"), selection: $themeManager.currentTheme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(LocalizedStringKey(theme.rawValue)).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                } header: {
                    Label(LocalizedStringKey("外观"), systemImage: "paintbrush")
                }

                // 隐私设置
                Section {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        Label(LocalizedStringKey("隐私设置"), systemImage: "lock.shield")
                    }
                } header: {
                    Label(LocalizedStringKey("隐私"), systemImage: "hand.raised")
                }

                // 通知设置
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label(LocalizedStringKey("通知设置"), systemImage: "bell.badge")
                    }
                } header: {
                    Label(LocalizedStringKey("通知"), systemImage: "app.badge")
                }

                // 关于
                Section {
                    HStack {
                        Text(LocalizedStringKey("版本"))
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        Label(LocalizedStringKey("用户协议"), systemImage: "doc.text")
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        Label(LocalizedStringKey("隐私政策"), systemImage: "lock.shield")
                    }
                } header: {
                    Label(LocalizedStringKey("关于"), systemImage: "info.circle")
                }

                // 退出登录
                Section {
                    Button(role: .destructive) {
                        Task {
                            try? await authService.signOut()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label(LocalizedStringKey("退出登录"), systemImage: "arrow.right.square")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(LocalizedStringKey("设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(LocalizedStringKey("完成")) {
                        dismiss()
                    }
                }
            }
            .alert(LocalizedStringKey("提示"), isPresented: $showAlert) {
                Button(LocalizedStringKey("确定"), role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
        }
    }
}

// MARK: - Notification Settings View

private struct NotificationSettingsView: View {
    @ObservedObject private var notificationManager = NotificationManager.shared

    @State private var enablePushNotifications = false
    @State private var enableMessageNotifications = true
    @State private var enableLikeNotifications = true
    @State private var enableCommentNotifications = true
    @State private var enableFollowNotifications = true
    @State private var showPermissionAlert = false

    var body: some View {
        List {
            Section {
                Toggle("启用推送通知", isOn: $enablePushNotifications)
                    .onChange(of: enablePushNotifications) { _, newValue in
                        if newValue {
                            Task {
                                await requestNotificationPermission()
                            }
                        } else {
                            UserDefaults.standard.set(false, forKey: "enable_push_notifications")
                        }
                    }

                if notificationManager.authorizationStatus == .denied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Text("通知权限已被拒绝，点击前往设置")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("推送通知")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("关闭后将不会收到任何通知")

                    if let token = notificationManager.deviceToken {
                        Text("设备已注册: \(token.prefix(8))...")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                }
            }

            Section {
                Toggle("私信通知", isOn: $enableMessageNotifications)
                    .disabled(!enablePushNotifications)
                    .onChange(of: enableMessageNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enable_message_notifications")
                    }

                Toggle("点赞通知", isOn: $enableLikeNotifications)
                    .disabled(!enablePushNotifications)
                    .onChange(of: enableLikeNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enable_like_notifications")
                    }

                Toggle("评论通知", isOn: $enableCommentNotifications)
                    .disabled(!enablePushNotifications)
                    .onChange(of: enableCommentNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enable_comment_notifications")
                    }

                Toggle("关注通知", isOn: $enableFollowNotifications)
                    .disabled(!enablePushNotifications)
                    .onChange(of: enableFollowNotifications) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "enable_follow_notifications")
                    }
            } header: {
                Text("通知类型")
            } footer: {
                Text("你可以单独控制每种类型的通知")
            }
        }
        .navigationTitle("通知设置")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadNotificationSettings()
        }
        .alert("需要通知权限", isPresented: $showPermissionAlert) {
            Button("取消", role: .cancel) {
                enablePushNotifications = false
            }
            Button("去设置") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        } message: {
            Text("请在系统设置中允许Melodii发送通知")
        }
    }

    private func loadNotificationSettings() async {
        await notificationManager.updateAuthorizationStatus()

        enablePushNotifications = notificationManager.authorizationStatus == .authorized
        enableMessageNotifications = UserDefaults.standard.bool(forKey: "enable_message_notifications")
        enableLikeNotifications = UserDefaults.standard.bool(forKey: "enable_like_notifications")
        enableCommentNotifications = UserDefaults.standard.bool(forKey: "enable_comment_notifications")
        enableFollowNotifications = UserDefaults.standard.bool(forKey: "enable_follow_notifications")
    }

    private func requestNotificationPermission() async {
        do {
            let granted = try await notificationManager.requestAuthorization()

            if granted {
                enablePushNotifications = true
                UserDefaults.standard.set(true, forKey: "enable_push_notifications")
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } else {
                enablePushNotifications = false
                showPermissionAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } catch {
            enablePushNotifications = false
            print("❌ 请求通知权限失败: \(error)")
        }
    }
}

// MARK: - Privacy Settings View

private struct PrivacySettingsView: View {
    @AppStorage("enable_read_receipts") private var enableReadReceipts = true
    @AppStorage("show_online_status") private var showOnlineStatus = true
    @AppStorage("allow_stranger_messages") private var allowStrangerMessages = true

    var body: some View {
        List {
            Section {
                Toggle("显示消息已读状态", isOn: $enableReadReceipts)
            } header: {
                Text("消息隐私")
            } footer: {
                Text("关闭后，对方将无法看到你是否已读他们的消息，同时你也无法看到对方的已读状态")
                    .font(.caption)
            }

            Section {
                Toggle("显示在线状态", isOn: $showOnlineStatus)
            } header: {
                Text("在线状态")
            } footer: {
                Text("关闭后，其他用户将无法看到你的在线状态")
                    .font(.caption)
            }

            Section {
                Toggle("允许陌生人发消息", isOn: $allowStrangerMessages)
            } header: {
                Text("消息接收")
            } footer: {
                Text("关闭后，只有你关注的人才能给你发送私信")
                    .font(.caption)
            }
        }
        .navigationTitle("隐私设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
}
