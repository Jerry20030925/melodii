//
//  MoodTrackerView.swift
//  Melodii
//
//  情绪追踪器 - 记录每天的心情，可视化情感旅程
//

import SwiftUI

struct MoodTrackerView: View {
    @State private var selectedMood: Mood?
    @State private var moodHistory: [MoodEntry] = []
    @State private var showMoodPicker = false
    @State private var note: String = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 今日情绪
                todayMoodSection

                // 情绪日历
                moodCalendarSection

                // 情绪统计
                moodStatsSection

                // 情绪趋势图
                moodTrendSection
            }
            .padding()
        }
        .navigationTitle("情绪日记")
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $showMoodPicker) {
            MoodPickerSheet(onSelect: { mood in
                saveMood(mood)
                showMoodPicker = false
            })
        }
        .onAppear {
            loadMoodHistory()
        }
    }

    // MARK: - Today Mood Section

    private var todayMoodSection: some View {
        VStack(spacing: 16) {
            Text("今天感觉如何？")
                .font(.title2)
                .fontWeight(.bold)

            if let todayMood = getTodayMood() {
                // 已记录今日情绪
                VStack(spacing: 12) {
                    Text(todayMood.mood.emoji)
                        .font(.system(size: 80))

                    Text(todayMood.mood.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    if let note = todayMood.note, !note.isEmpty {
                        Text(note)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    Text(todayMood.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(todayMood.mood.color.opacity(0.15))
                )
            } else {
                // 未记录
                Button {
                    showMoodPicker = true
                } label: {
                    VStack(spacing: 16) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )

                        Text("记录今天的心情")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemGray6))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Mood Calendar

    private var moodCalendarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近7天")
                .font(.headline)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible()), count: 7),
                spacing: 12
            ) {
                ForEach(getLast7Days(), id: \.self) { date in
                    VStack(spacing: 4) {
                        Text(dayLabel(for: date))
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if let mood = getMood(for: date) {
                            Text(mood.mood.emoji)
                                .font(.title2)
                        } else {
                            Circle()
                                .fill(Color(.systemGray5))
                                .frame(width: 32, height: 32)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }

    // MARK: - Mood Stats

    private var moodStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("情绪分析")
                .font(.headline)

            if !moodHistory.isEmpty {
                let stats = calculateMoodStats()

                VStack(spacing: 8) {
                    ForEach(stats.sorted(by: { $0.value > $1.value }), id: \.key.rawValue) { mood, count in
                        HStack {
                            Text(mood.emoji)
                                .font(.title3)

                            Text(mood.name)
                                .font(.subheadline)

                            Spacer()

                            Text("\(count) 次")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ProgressView(value: Double(count), total: Double(moodHistory.count))
                                .frame(width: 60)
                                .tint(mood.color)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } else {
                Text("开始记录情绪，了解自己的情感变化")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }

    // MARK: - Mood Trend

    private var moodTrendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("情绪趋势")
                .font(.headline)

            if moodHistory.count >= 3 {
                MoodTrendChart(entries: moodHistory)
                    .frame(height: 200)
            } else {
                Text("记录至少3天的情绪后可查看趋势")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
        )
    }

    // MARK: - Helper Methods

    private func getTodayMood() -> MoodEntry? {
        moodHistory.first { Calendar.current.isDateInToday($0.timestamp) }
    }

    private func getMood(for date: Date) -> MoodEntry? {
        moodHistory.first { Calendar.current.isDate($0.timestamp, inSameDayAs: date) }
    }

    private func getLast7Days() -> [Date] {
        (0..<7).compactMap { days in
            Calendar.current.date(byAdding: .day, value: -days, to: Date())
        }.reversed()
    }

    private func dayLabel(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return "今"
        } else if Calendar.current.isDateInYesterday(date) {
            return "昨"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "E"
            formatter.locale = Locale(identifier: "zh_CN")
            return formatter.string(from: date)
        }
    }

    private func calculateMoodStats() -> [Mood: Int] {
        var stats: [Mood: Int] = [:]
        for entry in moodHistory {
            stats[entry.mood, default: 0] += 1
        }
        return stats
    }

    private func saveMood(_ mood: Mood) {
        let entry = MoodEntry(mood: mood, note: note, timestamp: Date())
        moodHistory.insert(entry, at: 0)
        // TODO: 保存到本地或服务器
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func loadMoodHistory() {
        // TODO: 从本地或服务器加载
        // 示例数据
        moodHistory = []
    }
}

// MARK: - Mood Picker Sheet

private struct MoodPickerSheet: View {
    let onSelect: (Mood) -> Void

    @Environment(\.dismiss) private var dismiss

    let moods = Mood.allCases

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(moods, id: \.self) { mood in
                        Button {
                            onSelect(mood)
                        } label: {
                            VStack(spacing: 12) {
                                Text(mood.emoji)
                                    .font(.system(size: 60))

                                Text(mood.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Text(mood.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(20)
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(mood.color.opacity(0.15))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("选择心情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Mood Trend Chart

private struct MoodTrendChart: View {
    let entries: [MoodEntry]

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 背景网格
                Path { path in
                    for i in 0..<6 {
                        let y = geometry.size.height * CGFloat(i) / 5
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                // 情绪线
                if entries.count >= 2 {
                    Path { path in
                        let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
                        let maxValue = 5.0
                        let stepX = geometry.size.width / CGFloat(max(sortedEntries.count - 1, 1))

                        for (index, entry) in sortedEntries.enumerated() {
                            let x = CGFloat(index) * stepX
                            let y = geometry.size.height * (1 - CGFloat(entry.mood.value) / maxValue)

                            if index == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                    )

                    // 数据点
                    ForEach(Array(entries.sorted { $0.timestamp < $1.timestamp }.enumerated()), id: \.offset) { index, entry in
                        let stepX = geometry.size.width / CGFloat(max(entries.count - 1, 1))
                        let x = CGFloat(index) * stepX
                        let y = geometry.size.height * (1 - CGFloat(entry.mood.value) / 5.0)

                        Circle()
                            .fill(entry.mood.color)
                            .frame(width: 12, height: 12)
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}

// MARK: - Models

enum Mood: String, CaseIterable, Codable {
    case amazing = "amazing"
    case happy = "happy"
    case neutral = "neutral"
    case sad = "sad"
    case angry = "angry"

    var emoji: String {
        switch self {
        case .amazing: return "😄"
        case .happy: return "🙂"
        case .neutral: return "😐"
        case .sad: return "😢"
        case .angry: return "😠"
        }
    }

    var name: String {
        switch self {
        case .amazing: return "超棒"
        case .happy: return "开心"
        case .neutral: return "还行"
        case .sad: return "难过"
        case .angry: return "生气"
        }
    }

    var description: String {
        switch self {
        case .amazing: return "感觉棒极了"
        case .happy: return "心情不错"
        case .neutral: return "平平淡淡"
        case .sad: return "有点失落"
        case .angry: return "很不开心"
        }
    }

    var color: Color {
        switch self {
        case .amazing: return .green
        case .happy: return .blue
        case .neutral: return .gray
        case .sad: return .indigo
        case .angry: return .red
        }
    }

    var value: Double {
        switch self {
        case .amazing: return 5
        case .happy: return 4
        case .neutral: return 3
        case .sad: return 2
        case .angry: return 1
        }
    }
}

struct MoodEntry: Identifiable, Codable {
    let id = UUID()
    let mood: Mood
    let note: String?
    let timestamp: Date

    init(mood: Mood, note: String? = nil, timestamp: Date = Date()) {
        self.mood = mood
        self.note = note
        self.timestamp = timestamp
    }
}

#Preview {
    NavigationStack {
        MoodTrackerView()
    }
}
