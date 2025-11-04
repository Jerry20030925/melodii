//
//  MIDValidation.swift
//  Melodii
//
//  MID输入验证扩展
//

import Foundation

extension String {
    /// 验证MID格式：仅允许英文和数字，最大8个字符
    var isValidMID: Bool {
        // 检查长度
        guard count <= 8 && count > 0 else { return false }
        
        // 检查字符：仅允许英文字母和数字
        let allowedCharacters = CharacterSet.alphanumerics
        let characterSet = CharacterSet(charactersIn: self)
        
        return allowedCharacters.isSuperset(of: characterSet)
    }
    
    /// 格式化MID输入：移除非法字符，限制长度
    var formattedMID: String {
        // 只保留英文字母和数字
        let filtered = self.filter { character in
            character.isLetter || character.isNumber
        }
        
        // 限制长度为8个字符
        return String(filtered.prefix(8))
    }
    
    /// 获取MID验证错误信息
    var midValidationError: String? {
        if isEmpty {
            return "MID不能为空"
        }
        
        if count > 8 {
            return "MID不能超过8个字符"
        }
        
        let allowedCharacters = CharacterSet.alphanumerics
        let characterSet = CharacterSet(charactersIn: self)
        
        if !allowedCharacters.isSuperset(of: characterSet) {
            return "MID只能包含英文字母和数字"
        }
        
        return nil
    }
}

// MARK: - MID验证结果

struct MIDValidationResult {
    let isValid: Bool
    let errorMessage: String?
    let formattedMID: String
    
    init(input: String) {
        self.formattedMID = input.formattedMID
        self.errorMessage = formattedMID.midValidationError
        self.isValid = errorMessage == nil
    }
}

// MARK: - MID修改频率检查

struct MIDUpdateFrequencyChecker {
    /// 检查用户是否可以修改MID
    static func canUpdateMID(lastUpdateDate: Date?) -> Bool {
        guard let lastUpdate = lastUpdateDate else { return true }
        
        let calendar = Calendar.current
        let sixMonthsAgo = calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        
        return lastUpdate < sixMonthsAgo
    }
    
    /// 获取下次可修改MID的日期
    static func nextUpdateDate(lastUpdateDate: Date?) -> Date? {
        guard let lastUpdate = lastUpdateDate else { return nil }
        
        let calendar = Calendar.current
        return calendar.date(byAdding: .month, value: 6, to: lastUpdate)
    }
    
    /// 获取剩余等待时间的描述
    static func remainingWaitTimeDescription(lastUpdateDate: Date?) -> String? {
        guard let nextDate = nextUpdateDate(lastUpdateDate: lastUpdateDate) else { return nil }
        
        let calendar = Calendar.current
        let components = calendar.dateComponents([.month, .day], from: Date(), to: nextDate)
        
        if let months = components.month, months > 0 {
            if let days = components.day, days > 0 {
                return "\(months)个月\(days)天后可再次修改"
            } else {
                return "\(months)个月后可再次修改"
            }
        } else if let days = components.day, days > 0 {
            return "\(days)天后可再次修改"
        } else {
            return "今天可以修改"
        }
    }
}