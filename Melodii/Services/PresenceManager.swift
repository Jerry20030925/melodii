import Foundation
import Supabase
import Combine
import UIKit

@MainActor
final class PresenceManager: ObservableObject {
    static let shared = PresenceManager()
    private let client = SupabaseConfig.client

    @Published private(set) var onlineUsers: Set<String> = []
    // 记录用户开始在线的时间（用于在线时长显示）
    @Published private(set) var onlineStartTimes: [String: Date] = [:]

    private var presenceChannel: RealtimeChannelV2?
    private var heartbeatTimer: Timer?

    private init() {}

    // 登录后调用
    func connect(userId: String) async {
        await subscribePresence()
        trackOnline(userId: userId)
        startHeartbeat(userId: userId)
    }

    // 登出时调用
    func disconnect() async {
        await presenceChannel?.unsubscribe()
        presenceChannel = nil
        onlineUsers.removeAll()
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    private func subscribePresence() async {
        if let ch = presenceChannel {
            await ch.unsubscribe()
            presenceChannel = nil
        }
        let ch = client.realtimeV2.channel("presence:users") { opts in
            opts.broadcast.receiveOwnBroadcasts = true
        }
        presenceChannel = ch

        Task {
            for await change in ch.presenceChange() {
                // 解析 joins/leaves 的 user_id
                if let joins = try? change.decodeJoins(as: PresencePayload.self) {
                    for j in joins {
                        onlineUsers.insert(j.userId)
                        // 若此前未记录上线起点，现在记录（以收到 join 的本地时间为准）
                        if onlineStartTimes[j.userId] == nil {
                            onlineStartTimes[j.userId] = Date()
                        }
                    }
                }
                if let leaves = try? change.decodeLeaves(as: PresencePayload.self) {
                    for l in leaves {
                        onlineUsers.remove(l.userId)
                        onlineStartTimes.removeValue(forKey: l.userId)
                    }
                }
            }
        }

        do {
            try await ch.subscribeWithError()
        } catch {
            print("❌ presence 订阅失败: \(error)")
        }
    }

    private struct PresencePayload: Codable { let userId: String }

    func trackOnline(userId: String) {
        Task {
            do {
                try await presenceChannel?.track(PresencePayload(userId: userId))
                // 立即更新 last_seen & is_online
                try await SupabaseService.shared.setOnline(userId: userId, online: true)
                // 记录自己的上线起点，便于其他端显示；本端也保留以供 UI 使用
                if onlineStartTimes[userId] == nil {
                    onlineStartTimes[userId] = Date()
                }
            } catch {
                print("⚠️ presence track 失败: \(error)")
            }
        }
    }

    func untrack(userId: String) {
        Task {
            await presenceChannel?.untrack()
            try? await SupabaseService.shared.setOnline(userId: userId, online: false)
        }
    }

    private func startHeartbeat(userId: String) {
        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: true) { _ in
            Task {
                try? await SupabaseService.shared.touchLastSeen(userId: userId)
            }
        }
    }

    func isUserOnline(_ userId: String) -> Bool {
        return onlineUsers.contains(userId)
    }

    /// 查询用户在线时长；若未在线或无起点记录返回 nil
    func onlineDuration(for userId: String, now: Date = Date()) -> TimeInterval? {
        guard let start = onlineStartTimes[userId], isUserOnline(userId) else { return nil }
        return now.timeIntervalSince(start)
    }
}

