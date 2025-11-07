//
//  ErrorHandler.swift
//  Melodii
//
//  全局错误处理和崩溃预防服务
//

import Foundation
import UIKit
import os.log
import Combine

@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: AppError?
    @Published var showErrorAlert = false
    
    private let logger = Logger(subsystem: "com.melodii.app", category: "ErrorHandler")
    
    // 错误统计
    private var errorCounts: [String: Int] = [:]
    private let maxErrorCount = 10
    
    private init() {}
    
    // MARK: - Error Handling
    
    /// 处理应用错误
    func handle(_ error: Error, context: String = "") {
        logger.error("🚨 错误发生: \(error.localizedDescription) 上下文: \(context)")
        
        let appError = convertToAppError(error, context: context)
        
        // 更新错误统计
        let errorKey = appError.category.rawValue
        errorCounts[errorKey, default: 0] += 1
        
        // 如果某类错误太频繁，采取防护措施
        if errorCounts[errorKey, default: 0] > maxErrorCount {
            logger.critical("🔥 错误频率过高: \(errorKey)")
            handleFrequentError(category: appError.category)
            return
        }
        
        // 显示用户友好的错误信息
        currentError = appError
        showErrorAlert = true
        
        // 记录到系统日志
        recordError(appError)
    }
    
    /// 处理网络错误
    func handleNetworkError(_ error: Error, operation: String) {
        logger.error("🌐 网络错误: \(operation) - \(error.localizedDescription)")
        
        let networkError = AppError(
            category: .network,
            title: "网络连接问题",
            message: "请检查网络连接后重试",
            originalError: error,
            context: operation
        )
        
        handle(networkError)
    }
    
    /// 处理UI错误
    func handleUIError(_ error: Error, component: String) {
        logger.error("🖼️ UI错误: \(component) - \(error.localizedDescription)")
        
        let uiError = AppError(
            category: .ui,
            title: "界面显示问题",
            message: "界面加载遇到问题，请稍后重试",
            originalError: error,
            context: component
        )
        
        handle(uiError)
    }
    
    /// 处理数据错误
    func handleDataError(_ error: Error, operation: String) {
        logger.error("💾 数据错误: \(operation) - \(error.localizedDescription)")
        
        let dataError = AppError(
            category: .data,
            title: "数据处理问题",
            message: "数据处理遇到问题，请重试",
            originalError: error,
            context: operation
        )
        
        handle(dataError)
    }
    
    // MARK: - Recovery Actions
    
    /// 处理频繁出现的错误
    private func handleFrequentError(category: ErrorCategory) {
        logger.critical("🛡️ 启动错误防护: \(category.rawValue)")
        
        switch category {
        case .network:
            // 暂停网络请求一段时间
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5秒
                errorCounts[category.rawValue] = 0
            }
            
        case .memory:
            // 清理缓存
            clearCaches()
            
        case .ui:
            // 重置UI状态
            resetUIState()
            
        case .data:
            // 重置数据状态
            resetDataState()
            
        case .unknown:
            // 通用恢复
            performGeneralRecovery()
        }
    }
    
    /// 清理缓存
    private func clearCaches() {
        logger.info("🧹 清理应用缓存")
        
        // 清理URL缓存
        URLCache.shared.removeAllCachedResponses()
        
        // 清理图片缓存（如果有）
        // ImageCache.shared.clearAll()
        
        // 通知实时服务清理缓存
        Task {
            await RealtimeMessagingService.shared.clearAllCaches()
        }
    }
    
    /// 重置UI状态
    private func resetUIState() {
        logger.info("🔄 重置UI状态")
        currentError = nil
        showErrorAlert = false
    }
    
    /// 重置数据状态
    private func resetDataState() {
        logger.info("💾 重置数据状态")
        // 可以添加数据重置逻辑
    }
    
    /// 通用恢复操作
    private func performGeneralRecovery() {
        logger.info("🩹 执行通用恢复操作")
        clearCaches()
        resetUIState()
        
        // 重置错误计数
        errorCounts.removeAll()
    }
    
    // MARK: - Error Conversion
    
    /// 将系统错误转换为应用错误
    private func convertToAppError(_ error: Error, context: String) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        
        let category = determineErrorCategory(error)
        let (title, message) = getUserFriendlyMessage(for: error, category: category)
        
        return AppError(
            category: category,
            title: title,
            message: message,
            originalError: error,
            context: context
        )
    }
    
    /// 确定错误类别
    private func determineErrorCategory(_ error: Error) -> ErrorCategory {
        let errorCode = (error as NSError).code
        let domain = (error as NSError).domain
        
        // 网络错误
        if domain == NSURLErrorDomain {
            return .network
        }
        
        // 内存错误
        if errorCode == NSFileReadNoSuchFileError || 
           error.localizedDescription.contains("memory") {
            return .memory
        }
        
        // UI错误
        if domain.contains("UI") || domain.contains("View") {
            return .ui
        }
        
        // 数据错误
        if domain.contains("Core") || domain.contains("SQL") {
            return .data
        }
        
        return .unknown
    }
    
    /// 获取用户友好的错误信息
    private func getUserFriendlyMessage(for error: Error, category: ErrorCategory) -> (title: String, message: String) {
        switch category {
        case .network:
            return ("网络连接问题", "请检查网络连接后重试")
        case .memory:
            return ("内存不足", "请关闭其他应用后重试")
        case .ui:
            return ("界面显示问题", "界面加载遇到问题，请稍后重试")
        case .data:
            return ("数据处理问题", "数据处理遇到问题，请重试")
        case .unknown:
            return ("未知错误", "遇到未知问题，请重启应用")
        }
    }
    
    /// 记录错误到系统日志
    private func recordError(_ error: AppError) {
        let logMessage = """
        错误类别: \(error.category.rawValue)
        错误标题: \(error.title)
        错误信息: \(error.message)
        上下文: \(error.context)
        原始错误: \(error.originalError?.localizedDescription ?? "无")
        """
        
        logger.fault("\(logMessage)")
    }
    
    // MARK: - Public Methods
    
    /// 清除当前错误
    func clearError() {
        currentError = nil
        showErrorAlert = false
    }
    
    /// 获取错误统计
    func getErrorStatistics() -> [String: Int] {
        return errorCounts
    }
    
    /// 重置错误统计
    func resetErrorStatistics() {
        errorCounts.removeAll()
        logger.info("📊 错误统计已重置")
    }
}

// MARK: - Extensions

extension RealtimeMessagingService {
    func clearAllCaches() async {
        conversations.removeAll()
        messageStatuses.removeAll()
        typingUsers.removeAll()
        print("🧹 RealtimeMessagingService缓存已清理")
    }
}

// MARK: - Error Models

enum ErrorCategory: String, CaseIterable {
    case network = "网络"
    case memory = "内存"
    case ui = "界面"
    case data = "数据"
    case unknown = "未知"
}

struct AppError: Error, Identifiable {
    let id = UUID()
    let category: ErrorCategory
    let title: String
    let message: String
    let originalError: Error?
    let context: String
    let timestamp = Date()
    
    init(category: ErrorCategory, title: String, message: String, originalError: Error? = nil, context: String = "") {
        self.category = category
        self.title = title
        self.message = message
        self.originalError = originalError
        self.context = context
    }
}
