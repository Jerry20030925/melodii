//
//  NotificationItem.swift
//  Melodii
//

import Foundation
import SwiftUI

// UI-facing notification item with resolved relations
struct NotificationItem: Identifiable, Equatable {
    let id: String
    let type: NotificationType
    let actor: User
    let post: Post?
    var isRead: Bool
    let createdAt: Date
}

// A simple row view to display a notification item
struct NotificationRowView: View {
    let notification: NotificationItem

    private var titleText: String {
        let name = (notification.actor.nickname == "Loading...") ? "用户" : notification.actor.nickname
        switch notification.type {
        case .like:
            return "\(name) 赞了你的帖子"
        case .comment:
            return "\(name) 评论了你的帖子"
        case .reply:
            return "\(name) 回复了你的评论"
        case .follow:
            return "\(name) 关注了你"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar placeholder
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay(
                    Text(notification.actor.initials)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(notification.createdAt.timeAgoDisplay)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !notification.isRead {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 8)
    }
}

// Simple relative time helper if you don't already have one elsewhere
private extension Date {
    var timeAgoDisplay: String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 60 { return "刚刚" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) 小时前" }
        let days = hours / 24
        if days < 7 { return "\(days) 天前" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}
