//
//  ImageCacheManager.swift
//  Melodii
//
//  图片缓存管理器 - 优化图片加载性能
//

import Foundation
import UIKit
import SwiftUI
import Combine

@MainActor
class ImageCacheManager: ObservableObject {
    static let shared = ImageCacheManager()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxMemoryCacheCount = 100
    private let maxDiskCacheSize: Int64 = 100 * 1024 * 1024 // 100MB

    private init() {
        // 设置内存缓存限制
        cache.countLimit = maxMemoryCacheCount
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB

        // 创建磁盘缓存目录
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDirectory = cachesDirectory.appendingPathComponent("ImageCache", isDirectory: true)

        // 创建目录（如果不存在）
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // 监听内存警告
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        #endif

        // 清理过期缓存
        Task {
            await cleanExpiredCache()
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - 内存缓存

    /// 从内存缓存获取图片
    func getFromMemory(url: String) -> UIImage? {
        return cache.object(forKey: url as NSString)
    }

    /// 保存图片到内存缓存
    func saveToMemory(url: String, image: UIImage) {
        let cost = image.jpegData(compressionQuality: 1.0)?.count ?? 0
        cache.setObject(image, forKey: url as NSString, cost: cost)
    }

    // MARK: - 磁盘缓存

    /// 从磁盘缓存获取图片
    func getFromDisk(url: String) async -> UIImage? {
        let cacheKey = url.md5
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // 更新访问时间
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: fileURL.path
        )

        guard let data = try? Data(contentsOf: fileURL),
              let image = UIImage(data: data) else {
            return nil
        }

        // 同时保存到内存缓存
        await MainActor.run {
            saveToMemory(url: url, image: image)
        }

        return image
    }

    /// 保存图片到磁盘缓存
    func saveToDisk(url: String, image: UIImage) async {
        let cacheKey = url.md5
        let fileURL = cacheDirectory.appendingPathComponent(cacheKey)

        // 压缩图片以节省空间
        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        try? data.write(to: fileURL)

        // 检查磁盘缓存大小
        await checkDiskCacheSize()
    }

    // MARK: - 获取图片

    /// 获取图片（先检查缓存，再下载）
    func getImage(url: String) async -> UIImage? {
        // 1. 检查内存缓存
        if let cachedImage = getFromMemory(url: url) {
            print("✅ 从内存缓存加载图片: \(url)")
            return cachedImage
        }

        // 2. 检查磁盘缓存
        if let diskImage = await getFromDisk(url: url) {
            print("✅ 从磁盘缓存加载图片: \(url)")
            return diskImage
        }

        // 3. 从网络下载
        guard let imageURL = URL(string: url) else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: data) else {
                return nil
            }

            // 保存到缓存
            await MainActor.run {
                saveToMemory(url: url, image: image)
            }
            await saveToDisk(url: url, image: image)

            print("✅ 从网络下载图片: \(url)")
            return image

        } catch {
            print("❌ 下载图片失败: \(error)")
            return nil
        }
    }

    // MARK: - 缓存管理

    /// 清理内存缓存
    @objc private func handleMemoryWarning() {
        print("⚠️ 收到内存警告，清理图片缓存")
        cache.removeAllObjects()
    }

    /// 清理过期的磁盘缓存
    private func cleanExpiredCache() async {
        let expirationInterval: TimeInterval = 7 * 24 * 60 * 60 // 7天

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        let now = Date()
        for fileURL in fileURLs {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }

            // 删除超过7天未访问的文件
            if now.timeIntervalSince(modificationDate) > expirationInterval {
                try? fileManager.removeItem(at: fileURL)
                print("🗑️ 清理过期缓存: \(fileURL.lastPathComponent)")
            }
        }
    }

    /// 检查磁盘缓存大小并清理
    private func checkDiskCacheSize() async {
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        // 计算总大小
        var totalSize: Int64 = 0
        var files: [(url: URL, size: Int64, date: Date)] = []

        for fileURL in fileURLs {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let fileSize = attributes[.size] as? Int64,
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }

            totalSize += fileSize
            files.append((fileURL, fileSize, modificationDate))
        }

        // 如果超过限制，删除最旧的文件
        if totalSize > maxDiskCacheSize {
            print("⚠️ 磁盘缓存超过限制(\(totalSize / 1024 / 1024)MB)，开始清理")

            // 按修改日期排序（最旧的在前）
            files.sort { $0.date < $1.date }

            for file in files {
                guard totalSize > maxDiskCacheSize / 2 else { break }

                try? fileManager.removeItem(at: file.url)
                totalSize -= file.size
                print("🗑️ 清理缓存文件: \(file.url.lastPathComponent)")
            }
        }
    }

    /// 清空所有缓存
    func clearAll() {
        cache.removeAllObjects()

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return
        }

        for fileURL in fileURLs {
            try? fileManager.removeItem(at: fileURL)
        }

        print("✅ 已清空所有图片缓存")
    }
}

// MARK: - String MD5扩展

extension String {
    var md5: String {
        let data = Data(self.utf8)
        let hash = data.withUnsafeBytes { bytes -> [UInt8] in
            var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
            CC_MD5(bytes.baseAddress, CC_LONG(data.count), &hash)
            return hash
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

import CommonCrypto

// MARK: - SwiftUI 缓存图片视图

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: String
    let content: (UIImage) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                content(image)
            } else {
                placeholder()
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        guard !isLoading else { return }
        isLoading = true

        image = await ImageCacheManager.shared.getImage(url: url)
        isLoading = false
    }
}

// MARK: - 便捷初始化

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: String, @ViewBuilder content: @escaping (UIImage) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { ProgressView() }
    }
}
