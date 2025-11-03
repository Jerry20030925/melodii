//
//  UnreadCenter.swift
//  Melodii
//
//  Created by Assistant on 31/10/2025.
//

import Foundation
import Observation

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

    // Notifications
    func incrementNotifications(by delta: Int = 1) {
        unreadNotifications = max(0, unreadNotifications + delta)
    }

    func decrementNotifications(by delta: Int = 1) {
        unreadNotifications = max(0, unreadNotifications - delta)
    }

    // Messages
    func incrementMessages(by delta: Int = 1) {
        unreadMessages = max(0, unreadMessages + delta)
    }

    func decrementMessages(by delta: Int = 1) {
        unreadMessages = max(0, unreadMessages - delta)
    }
}
