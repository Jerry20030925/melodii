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
        let videoExtensions = [".mp4", ".mov", ".m4v", ".avi", ".mkv", ".webm", ".3gp", ".flv", ".wmv", ".mpg", ".mpeg"]
        return videoExtensions.contains { lower.hasSuffix($0) }
    }
    
    /// 检测字符串是否为图片URL
    var isImageURL: Bool {
        let lower = self.lowercased()
        let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".webp", ".heic", ".heif"]
        return imageExtensions.contains { lower.hasSuffix($0) }
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