//
//  Date+Extensions.swift
//  Melodii
//
//  Created by Claude Code on 30/10/2025.
//

import Foundation

extension Date {
    /// 获取相对于现在的时间描述，不显示秒数
    /// 例如: "刚刚", "5分钟前", "2小时前", "3天前"
    var timeAgoDisplay: String {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: self, to: now)

        if let year = components.year, year >= 1 {
            return year == 1 ? "1年前" : "\(year)年前"
        }

        if let month = components.month, month >= 1 {
            return month == 1 ? "1个月前" : "\(month)个月前"
        }

        if let day = components.day, day >= 1 {
            return day == 1 ? "1天前" : "\(day)天前"
        }

        if let hour = components.hour, hour >= 1 {
            return hour == 1 ? "1小时前" : "\(hour)小时前"
        }

        if let minute = components.minute, minute >= 1 {
            return minute == 1 ? "1分钟前" : "\(minute)分钟前"
        }

        return "刚刚"
    }
}
