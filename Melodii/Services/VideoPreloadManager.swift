//
//  VideoPreloadManager.swift
//  Melodii
//
//  视频预加载管理器
//

import Foundation
import AVFoundation
import Combine

@MainActor
class VideoPreloadManager: ObservableObject {
    static let shared = VideoPreloadManager()
    
    private var preloadedItems: [String: AVPlayerItem] = [:]
    private var preloadTasks: [String: Task<Void, Never>] = [:]
    private let maxPreloadCount = 5 // 最大预加载数量
    
    private init() {}
    
    /// 预加载视频
    func preloadVideo(url: String) {
        guard !preloadedItems.keys.contains(url),
              !preloadTasks.keys.contains(url),
              let videoURL = URL(string: url) else {
            return
        }
        
        // 如果超过最大预加载数量，移除最旧的
        if preloadedItems.count >= maxPreloadCount {
            let oldestKey = preloadedItems.keys.first
            if let key = oldestKey {
                preloadedItems.removeValue(forKey: key)
            }
        }
        
        let task = Task {
            let item = AVPlayerItem(url: videoURL)

            // 等待视频准备就绪
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                var observer: NSKeyValueObservation?
                var hasResumed = false

                observer = item.observe(\.status, options: [.new]) { item, _ in
                    guard !hasResumed else { return }

                    if item.status == .readyToPlay || item.status == .failed {
                        hasResumed = true
                        observer?.invalidate()
                        continuation.resume()
                    }
                }

                // 设置超时
                DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                    guard !hasResumed else { return }
                    hasResumed = true
                    observer?.invalidate()
                    continuation.resume()
                }
            }

            if item.status == .readyToPlay {
                await MainActor.run {
                    preloadedItems[url] = item
                }
                print("✅ 视频预加载成功: \(url)")
            } else {
                print("❌ 视频预加载失败: \(url)")
            }

            await MainActor.run {
                preloadTasks.removeValue(forKey: url)
            }
        }
        
        preloadTasks[url] = task
    }
    
    /// 获取预加载的视频项目
    func getPreloadedItem(url: String) -> AVPlayerItem? {
        return preloadedItems[url]
    }
    
    /// 移除预加载的视频
    func removePreloadedVideo(url: String) {
        preloadedItems.removeValue(forKey: url)
        preloadTasks[url]?.cancel()
        preloadTasks.removeValue(forKey: url)
    }
    
    /// 清理所有预加载的视频
    func clearAll() {
        preloadedItems.removeAll()
        preloadTasks.values.forEach { $0.cancel() }
        preloadTasks.removeAll()
    }
    
    /// 预加载视频列表
    func preloadVideos(urls: [String]) {
        for url in urls.prefix(maxPreloadCount) {
            if url.isVideoURL {
                preloadVideo(url: url)
            }
        }
    }
}

// MARK: - 视频播放器助手

extension VideoPreloadManager {
    /// 创建优化的播放器
    func createOptimizedPlayer(url: String) -> AVPlayer? {
        guard let videoURL = URL(string: url) else { return nil }
        
        // 尝试使用预加载的项目
        if let preloadedItem = getPreloadedItem(url: url) {
            print("🚀 使用预加载的视频: \(url)")
            return AVPlayer(playerItem: preloadedItem)
        }
        
        // 创建新的播放器
        return AVPlayer(url: videoURL)
    }
    
    /// 创建优化的队列播放器（用于循环播放）
    func createOptimizedQueuePlayer(url: String) -> (AVQueuePlayer, AVPlayerLooper)? {
        guard let videoURL = URL(string: url) else { return nil }
        
        let item: AVPlayerItem
        if let preloadedItem = getPreloadedItem(url: url) {
            item = preloadedItem
            print("🚀 使用预加载的循环视频: \(url)")
        } else {
            item = AVPlayerItem(url: videoURL)
        }
        
        let player = AVQueuePlayer(items: [item])
        let looper = AVPlayerLooper(player: player, templateItem: item)
        
        return (player, looper)
    }
}