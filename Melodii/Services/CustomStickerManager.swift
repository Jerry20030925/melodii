//
//  CustomStickerManager.swift
//  Melodii
//
//  自定义表情包管理器 - 支持上传和管理用户自定义表情包
//

import Foundation
import SwiftUI
import UIKit
import Combine

// MARK: - Custom Sticker Model

struct CustomSticker: Codable, Identifiable {
    let id: String
    let userId: String
    let imageURL: String
    let name: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case imageURL = "image_url"
        case name
        case createdAt = "created_at"
    }
}

// MARK: - Custom Sticker Manager

@MainActor
class CustomStickerManager: ObservableObject {
    static let shared = CustomStickerManager()

    @Published var customStickers: [CustomSticker] = []
    @Published var isLoading = false

    private init() {
        loadStickers()
    }

    // MARK: - Load Stickers

    func loadStickers() {
        guard let userId = AuthService.shared.currentUser?.id else { return }

        Task {
            isLoading = true
            defer { isLoading = false }

            do {
                customStickers = try await SupabaseService.shared.fetchCustomStickers(userId: userId)
            } catch {
                print("❌ 加载自定义表情包失败: \(error)")
            }
        }
    }

    // MARK: - Add Sticker

    func addSticker(image: UIImage, name: String? = nil) async throws -> CustomSticker {
        guard let userId = AuthService.shared.currentUser?.id else {
            throw StickerError.notAuthenticated
        }

        // 压缩图片
        guard let imageData = compressImage(image, maxBytes: 500_000) else {
            throw StickerError.imageCompressionFailed
        }

        isLoading = true
        defer { isLoading = false }

        // 上传图片
        let folder = "stickers/\(userId)"
        let imageURL = try await SupabaseService.shared.uploadPostMediaWithProgress(
            data: imageData,
            mime: "image/jpeg",
            fileName: nil,
            folder: folder,
            bucket: "media",
            isPublic: true,
            onProgress: { _ in }
        )

        // 保存到数据库
        let sticker = try await SupabaseService.shared.createCustomSticker(
            userId: userId,
            imageURL: imageURL,
            name: name
        )

        // 添加到本地列表
        customStickers.append(sticker)

        return sticker
    }

    // MARK: - Delete Sticker

    func deleteSticker(_ sticker: CustomSticker) async throws {
        isLoading = true
        defer { isLoading = false }

        try await SupabaseService.shared.deleteCustomSticker(stickerId: sticker.id)

        // 从本地列表移除
        customStickers.removeAll { $0.id == sticker.id }
    }

    // MARK: - Utilities

    private func compressImage(_ image: UIImage, maxBytes: Int) -> Data? {
        // 首先调整尺寸
        let maxSize: CGFloat = 512
        let size = image.size
        let scale = min(1.0, maxSize / max(size.width, size.height))
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let resized = resizedImage else { return nil }

        // 压缩质量
        var quality: CGFloat = 0.8
        var data = resized.jpegData(compressionQuality: quality)

        while let d = data, d.count > maxBytes && quality > 0.3 {
            quality -= 0.1
            data = resized.jpegData(compressionQuality: quality)
        }

        return data
    }
}

// MARK: - Errors

enum StickerError: LocalizedError {
    case notAuthenticated
    case imageCompressionFailed
    case uploadFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "请先登录"
        case .imageCompressionFailed:
            return "图片处理失败"
        case .uploadFailed:
            return "上传失败"
        case .deleteFailed:
            return "删除失败"
        }
    }
}
