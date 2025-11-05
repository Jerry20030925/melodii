//
//  PostDeleteNotification.swift
//  Melodii
//
//  帖子删除通知：用于同步删除事件
//

import Foundation

extension Foundation.Notification.Name {
    static let postDeleted = Foundation.Notification.Name("PostDeleted")
}

struct PostDeletedInfo {
    let postId: String
}
