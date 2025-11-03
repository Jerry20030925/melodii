//
//  UnreadCenter.swift
//  Melodii
//
//  全局未读中心：通知/消息未读计数
//

import Foundation
import Combine

@MainActor
final class UnreadCenter: ObservableObject {
    static let shared = UnreadCenter()

    @Published var unreadNotifications: Int = 0
    @Published var unreadMessages: Int = 0

    private init() {}

    func reset() {
        unreadNotifications = 0
        unreadMessages = 0
    }

    func incrementNotifications() {
        unreadNotifications = max(0, unreadNotifications + 1)
    }

    func incrementMessages() {
        unreadMessages = max(0, unreadMessages + 1)
    }

    func decrementMessages(_ count: Int = 1) {
        unreadMessages = max(0, unreadMessages - count)
    }
}
