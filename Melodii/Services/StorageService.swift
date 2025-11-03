//
//  StorageService.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation
import UIKit
import Supabase
import Combine

@MainActor
class StorageService: ObservableObject {
    static let shared = StorageService()

    private let client = SupabaseConfig.client
    private let bucketName = "media" // Supabase存储桶名称

    private init() {}

    // MARK: - Image Upload

    /// 上传图片
    /// - Parameters:
    ///   - image: UIImage对象
    ///   - userId: 用户ID（用于文件路径）
    /// - Returns: 上传后的公开URL
    func uploadImage(_ image: UIImage, userId: String) async throws -> String {
        // 压缩图片
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw StorageError.compressionFailed
        }

        // 生成唯一文件名
        let fileName = "\(userId)/\(UUID().uuidString).jpg"

        // 上传到Supabase Storage
        try await client.storage
            .from(bucketName)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        // 获取公开URL
        let publicURL = try client.storage
            .from(bucketName)
            .getPublicURL(path: fileName)

        return publicURL.absoluteString
    }

    /// 批量上传图片
    /// - Parameters:
    ///   - images: UIImage数组
    ///   - userId: 用户ID
    /// - Returns: 上传后的公开URL数组
    func uploadImages(_ images: [UIImage], userId: String) async throws -> [String] {
        var urls: [String] = []

        for image in images {
            let url = try await uploadImage(image, userId: userId)
            urls.append(url)
        }

        return urls
    }

    /// 删除图片
    /// - Parameter path: 文件路径（从URL中提取）
    func deleteImage(url: String) async throws {
        // 从URL中提取文件路径
        guard let path = extractPathFromURL(url) else {
            throw StorageError.invalidURL
        }

        try await client.storage
            .from(bucketName)
            .remove(paths: [path])
    }

    // MARK: - Avatar Upload

    /// 上传用户头像
    /// - Parameters:
    ///   - image: UIImage对象
    ///   - userId: 用户ID
    /// - Returns: 上传后的公开URL
    func uploadAvatar(_ image: UIImage, userId: String) async throws -> String {
        // 压缩头像（头像可以更小）
        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
            throw StorageError.compressionFailed
        }

        let fileName = "\(userId)/avatar.jpg"

        // 如果已存在旧头像，先删除
        try? await client.storage
            .from(bucketName)
            .remove(paths: [fileName])

        // 上传新头像
        try await client.storage
            .from(bucketName)
            .upload(
                path: fileName,
                file: imageData,
                options: FileOptions(contentType: "image/jpeg")
            )

        // 获取公开URL
        let publicURL = try client.storage
            .from(bucketName)
            .getPublicURL(path: fileName)

        return publicURL.absoluteString
    }

    // MARK: - Video Upload

    /// 上传视频（MP4默认）
    /// - Parameters:
    ///   - data: 视频二进制数据
    ///   - userId: 用户ID
    ///   - fileExtension: 文件扩展名（默认 mp4）
    /// - Returns: 上传后的公开URL
    func uploadVideo(_ data: Data, userId: String, fileExtension: String = "mp4") async throws -> String {
        let fileName = "videos/\(userId)/\(UUID().uuidString).\(fileExtension)"

        try await client.storage
            .from(bucketName)
            .upload(
                path: fileName,
                file: data,
                options: FileOptions(contentType: "video/mp4")
            )

        let publicURL = try client.storage
            .from(bucketName)
            .getPublicURL(path: fileName)

        return publicURL.absoluteString
    }

    /// 批量上传视频
    func uploadVideos(_ videos: [Data], userId: String) async throws -> [String] {
        var urls: [String] = []
        for data in videos {
            let url = try await uploadVideo(data, userId: userId)
            urls.append(url)
        }
        return urls
    }

    // MARK: - Helper Methods

    private func extractPathFromURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let bucketIndex = url.pathComponents.firstIndex(of: bucketName),
              bucketIndex + 1 < url.pathComponents.count else {
            return nil
        }

        let pathComponents = Array(url.pathComponents[(bucketIndex + 1)...])
        return pathComponents.joined(separator: "/")
    }
}

// MARK: - Storage Errors

enum StorageError: LocalizedError {
    case compressionFailed
    case invalidURL
    case uploadFailed

    var errorDescription: String? {
        switch self {
        case .compressionFailed:
            return "图片压缩失败"
        case .invalidURL:
            return "无效的URL"
        case .uploadFailed:
            return "上传失败"
        }
    }
}
