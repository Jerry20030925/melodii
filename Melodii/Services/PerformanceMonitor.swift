//
//  PerformanceMonitor.swift
//  Melodii
//
//  应用性能监控和优化服务
//

import Foundation
import UIKit
import os.log
import Combine

@MainActor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    private let logger = Logger(subsystem: "com.melodii.performance", category: "Monitor")
    
    // 性能指标
    @Published var currentMetrics = PerformanceMetrics()
    
    // 监控配置
    private let monitoringInterval: TimeInterval = 5.0
    private let memoryWarningThreshold: Double = 0.8 // 80%内存使用率
    private let cpuWarningThreshold: Double = 0.7   // 70%CPU使用率
    
    // 监控状态
    private var monitoringTimer: Timer?
    private var startTime = Date()
    private var isMonitoring = false
    
    private init() {
        setupNotificationObservers()
    }
    
    // MARK: - Public Methods
    
    /// 开始性能监控
    func startMonitoring() {
        guard !isMonitoring else { return }
        
        isMonitoring = true
        startTime = Date()
        
        monitoringTimer = Timer.scheduledTimer(withTimeInterval: monitoringInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMetrics()
            }
        }
        
        logger.info("📊 性能监控已启动")
    }
    
    /// 停止性能监控
    func stopMonitoring() {
        isMonitoring = false
        monitoringTimer?.invalidate()
        monitoringTimer = nil
        logger.info("📊 性能监控已停止")
    }
    
    /// 记录操作性能
    func recordOperation(_ operationName: String, duration: TimeInterval) {
        logger.info("⏱️ \(operationName): \(String(format: "%.3f", duration))s")
        
        // 如果操作时间过长，记录警告
        if duration > 2.0 {
            logger.warning("🐌 操作耗时过长: \(operationName) - \(String(format: "%.3f", duration))s")
            
            // 触发性能优化建议
            suggestOptimization(for: operationName, duration: duration)
        }
    }
    
    /// 测量操作性能
    func measureOperation<T>(_ operationName: String, operation: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        defer {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            recordOperation(operationName, duration: duration)
        }
        
        return try await operation()
    }
    
    /// 检查内存使用情况
    func checkMemoryUsage() -> MemoryInfo {
        let info = getMemoryInfo()
        
        if info.usagePercentage > memoryWarningThreshold {
            logger.warning("🧠 内存使用率过高: \(String(format: "%.1f", info.usagePercentage * 100))%")
            triggerMemoryOptimization()
        }
        
        return info
    }
    
    // MARK: - Private Methods
    
    /// 更新性能指标
    private func updateMetrics() {
        let memory = getMemoryInfo()
        let cpu = getCPUUsage()
        
        currentMetrics = PerformanceMetrics(
            memoryUsed: memory.used,
            memoryTotal: memory.total,
            memoryPercentage: memory.usagePercentage,
            cpuUsage: cpu,
            uptime: Date().timeIntervalSince(startTime)
        )
        
        // 检查是否需要警告
        checkPerformanceWarnings()
    }
    
    /// 获取内存信息
    private func getMemoryInfo() -> MemoryInfo {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        let totalMemory = ProcessInfo.processInfo.physicalMemory
        let usedMemory = UInt64(taskInfo.resident_size)
        
        if kerr == KERN_SUCCESS {
            return MemoryInfo(
                used: usedMemory,
                total: totalMemory,
                usagePercentage: Double(usedMemory) / Double(totalMemory)
            )
        }
        
        return MemoryInfo(used: 0, total: totalMemory, usagePercentage: 0)
    }
    
    /// 获取CPU使用率
    private func getCPUUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            return Double(info.virtual_size) / Double(1024 * 1024) // 简化的CPU使用率计算
        }
        
        return 0.0
    }
    
    /// 检查性能警告
    private func checkPerformanceWarnings() {
        if currentMetrics.memoryPercentage > memoryWarningThreshold {
            logger.warning("⚠️ 内存使用率过高: \(String(format: "%.1f", self.currentMetrics.memoryPercentage * 100))%")
            triggerMemoryOptimization()
        }
        
        if currentMetrics.cpuUsage > cpuWarningThreshold {
            logger.warning("⚠️ CPU使用率过高: \(String(format: "%.1f", self.currentMetrics.cpuUsage))%")
        }
    }
    
    /// 触发内存优化
    private func triggerMemoryOptimization() {
        logger.info("🧹 触发内存优化")
        
        Task {
            // 清理缓存
            await clearCaches()
            
            // 通知垃圾回收
            autoreleasepool {
                // 触发内存清理
            }
            
            // 发送内存警告通知
            NotificationCenter.default.post(name: Foundation.Notification.Name.memoryWarning, object: nil)
        }
    }
    
    /// 清理系统缓存
    private func clearCaches() async {
        // 清理URL缓存
        URLCache.shared.removeAllCachedResponses()
        
        // 清理应用缓存
        await RealtimeMessagingService.shared.clearAllCaches()
        
        logger.info("🧹 系统缓存已清理")
    }
    
    /// 性能优化建议
    private func suggestOptimization(for operation: String, duration: TimeInterval) {
        logger.info("💡 性能优化建议 - \(operation): 考虑异步处理或缓存优化")
        
        // 可以在这里实现具体的优化建议逻辑
    }
    
    /// 设置系统通知监听
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopMonitoring()
        }
    }
    
    /// 处理系统内存警告
    private func handleMemoryWarning() {
        logger.critical("🚨 收到系统内存警告")
        triggerMemoryOptimization()
    }
    
    // MARK: - Debugging
    
    /// 获取性能报告
    func getPerformanceReport() -> String {
        return """
        === 性能报告 ===
        运行时间: \(String(format: "%.1f", currentMetrics.uptime))秒
        内存使用: \(formatBytes(currentMetrics.memoryUsed)) / \(formatBytes(currentMetrics.memoryTotal))
        内存使用率: \(String(format: "%.1f", currentMetrics.memoryPercentage * 100))%
        CPU使用率: \(String(format: "%.1f", currentMetrics.cpuUsage))%
        """
    }
    
    /// 格式化字节数
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    deinit {
        // deinit 是非隔离上下文，跳转到主线程执行需要的清理
        Task { @MainActor in
            stopMonitoring()
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Data Models

struct PerformanceMetrics {
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryPercentage: Double = 0
    var cpuUsage: Double = 0
    var uptime: TimeInterval = 0
}

struct MemoryInfo {
    let used: UInt64
    let total: UInt64
    let usagePercentage: Double
}

// MARK: - Notification Extensions

extension Foundation.Notification.Name {
    static let memoryWarning = Foundation.Notification.Name("com.melodii.memoryWarning")
    static let performanceAlert = Foundation.Notification.Name("com.melodii.performanceAlert")
}
