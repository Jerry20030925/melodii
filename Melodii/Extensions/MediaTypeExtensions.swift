//
//  MediaTypeExtensions.swift
//  Melodii
//
//  媒体类型检测扩展
//

import Foundation

extension String {
    /// 检测字符串是否为视频URL
    var isVideoURL: Bool {
        let lower = self.lowercased()

        // 移除查询参数和fragment
        let urlWithoutParams: String
        if let questionMarkIndex = lower.firstIndex(of: "?") {
            urlWithoutParams = String(lower[..<questionMarkIndex])
        } else if let hashIndex = lower.firstIndex(of: "#") {
            urlWithoutParams = String(lower[..<hashIndex])
        } else {
            urlWithoutParams = lower
        }

        // 检查文件扩展名
        let videoExtensions = [".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp", ".flv", ".wmv", ".mpg", ".mpeg"]

        // 检查是否包含 "videos/" 路径（Supabase存储的视频路径）
        let hasVideosPath = urlWithoutParams.contains("/videos/")

        // 如果路径包含 "videos/" 或者扩展名匹配，则认为是视频
        return hasVideosPath || videoExtensions.contains { urlWithoutParams.hasSuffix($0) }
    }
    
    /// 检测字符串是否为图片URL
    var isImageURL: Bool {
        // 如果已经是视频，则不是图片
        if isVideoURL { return false }

        let lower = self.lowercased()

        // 移除查询参数和fragment
        let urlWithoutParams: String
        if let questionMarkIndex = lower.firstIndex(of: "?") {
            urlWithoutParams = String(lower[..<questionMarkIndex])
        } else if let hashIndex = lower.firstIndex(of: "#") {
            urlWithoutParams = String(lower[..<hashIndex])
        } else {
            urlWithoutParams = lower
        }

        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".heic", ".heif"]
        return imageExtensions.contains { urlWithoutParams.hasSuffix($0) }
    }
    
    /// 检测字符串是否为音频URL
    var isAudioURL: Bool {
        let lower = self.lowercased()
        let audioExtensions = [".mp3", ".wav", ".aac", ".m4a", ".flac", ".ogg", ".wma"]
        return audioExtensions.contains { lower.hasSuffix($0) }
    }
    
    /// 获取媒体类型
    var mediaType: MediaType {
        if isVideoURL { return .video }
        if isImageURL { return .image }
        if isAudioURL { return .audio }
        return .unknown
    }
}

enum MediaType {
    case video
    case image
    case audio
    case unknown
    
    var displayName: String {
        switch self {
        case .video: return "视频"
        case .image: return "图片"
        case .audio: return "音频"
        case .unknown: return "未知"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .video: return "video.fill"
        case .image: return "photo.fill"
        case .audio: return "music.note"
        case .unknown: return "doc.fill"
        }
    }
}