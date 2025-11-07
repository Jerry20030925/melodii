//
//  MoodDiaryView.swift
//  Melodii
//
//  情绪日记功能 - 记录和追踪用户的情绪变化
//

import SwiftUI
import SwiftData
import Foundation
import Supabase
import PostgREST

// MARK: - Mood Types

enum MoodType: String, CaseIterable {
    case happy = "开心"
    case excited = "兴奋"
    case calm = "平静"
    case sad = "难过"
    case angry = "愤怒"
    case anxious = "焦虑"
    case tired = "疲惫"
    case grateful = "感激"
    
    var emoji: String {
        switch self {
        case .happy: return "😊"
        case .excited: return "🤩"
        case .calm: return "😌"
        case .sad: return "😢"
        case .angry: return "😠"
        case .anxious: return "😰"
        case .tired: return "😴"
        case .grateful: return "🙏"
        }
    }
    
    var color: Color {
        switch self {
        case .happy: return .yellow
        case .excited: return .orange
        case .calm: return .blue
        case .sad: return .indigo
        case .angry: return .red
        case .anxious: return .purple
        case .tired: return .gray
        case .grateful: return .green
        }
    }
}

// MARK: - Mood Diary Entry Model

struct MoodDiaryEntry: Codable, Identifiable {
    let id: String
    let userId: String
    let mood: String
    let note: String?
    let intensity: Int // 1-10
    let createdAt: Date
    
    init(id: String = UUID().uuidString, userId: String, mood: String, note: String? = nil, intensity: Int, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.mood = mood
        self.note = note
        self.intensity = intensity
        self.createdAt = createdAt
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case mood
        case note
        case intensity
        case createdAt = "created_at"
    }
}

struct MoodDiaryView: View {
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @Environment(\.dismiss) private var dismiss
    
    // 当前记录状态
    @State private var selectedMood: MoodType?
    @State private var moodIntensity: Double = 5.0
    @State private var moodNote: String = ""
    @State private var isSaving = false
    
    // 历史记录
    @State private var moodEntries: [MoodDiaryEntry] = []
    @State private var isLoadingHistory = false
    
    // UI状态
    @State private var showConfirmation = false
    @State private var selectedTab = 0 // 0: 记录, 1: 历史
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 背景渐变
                LinearGradient(
                    colors: [
                        selectedMood?.color.opacity(0.1) ?? Color(.systemBackground),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部选项卡
                    tabSelector
                    
                    // 内容区域
                    TabView(selection: $selectedTab) {
                        recordMoodView
                            .tag(0)
                        
                        historyView
                            .tag(1)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("情绪日记")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        dismiss()
                    }
                }
                
                if selectedTab == 0 && selectedMood != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("保存") {
                            Task { await saveMoodEntry() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .task {
                await loadMoodHistory()
            }
            .alert("记录已保存", isPresented: $showConfirmation) {
                Button("确定") {
                    resetForm()
                }
            } message: {
                Text("你的情绪日记已成功保存")
            }
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack {
            ForEach(Array(zip([0, 1], ["记录情绪", "历史记录"]).enumerated()), id: \.offset) { index, item in
                let (tab, title) = item
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(selectedTab == tab ? .white : .primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            Group {
                                if selectedTab == tab {
                                    LinearGradient(
                                        colors: [.pink, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    Color.clear
                                }
                            }
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Record Mood View
    
    private var recordMoodView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 32) {
                // 情绪选择
                moodSelection
                
                // 强度滑块
                if selectedMood != nil {
                    intensitySlider
                }
                
                // 备注输入
                if selectedMood != nil {
                    noteInput
                }
                
                Spacer(minLength: 100)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var moodSelection: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("今天的心情如何？")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("选择最符合你当前感受的情绪")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(MoodType.allCases, id: \.self) { mood in
                    MoodCard(
                        mood: mood,
                        isSelected: selectedMood == mood
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedMood = mood
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
            }
        }
    }
    
    private var intensitySlider: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("情绪强度")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("1 (轻微) - 10 (强烈)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("1")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(moodIntensity))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(selectedMood?.color ?? .primary)
                    
                    Spacer()
                    
                    Text("10")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Slider(value: $moodIntensity, in: 1...10, step: 1)
                    .tint(selectedMood?.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    
    private var noteInput: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("备注 (可选)")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("记录一些想法或发生的事情")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            TextField("今天发生了什么让你有这种感受？", text: $moodNote, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(minHeight: 80)
        }
    }
    
    // MARK: - History View
    
    private var historyView: some View {
        Group {
            if isLoadingHistory {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("加载中...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if moodEntries.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart.text.square")
                        .font(.system(size: 60))
                        .foregroundStyle(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("还没有情绪记录")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("开始记录你的第一个情绪日记")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Button("记录情绪") {
                        selectedTab = 0
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 16) {
                        ForEach(moodEntries, id: \.id) { entry in
                            MoodHistoryCard(entry: entry)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
        }
    }
    
    // MARK: - Data Operations
    
    private func saveMoodEntry() async {
        guard let mood = selectedMood,
              let userId = authService.currentUser?.id else { return }
        
        isSaving = true
        
        do {
            let entry = MoodDiaryEntry(
                userId: userId,
                mood: mood.rawValue,
                note: moodNote.isEmpty ? nil : moodNote,
                intensity: Int(moodIntensity)
            )
            
            // Encodable payload matching table schema
            struct MoodInsert: Encodable {
                let id: String
                let user_id: String
                let mood: String
                let note: String?
                let intensity: Int
                let created_at: String
            }
            
            let payload = MoodInsert(
                id: entry.id,
                user_id: entry.userId,
                mood: entry.mood,
                note: entry.note,
                intensity: entry.intensity,
                created_at: ISO8601DateFormatter().string(from: entry.createdAt)
            )
            
            try await supabaseService.client
                .from("mood_entries")
                .insert(payload)
                .execute()
            
            // 更新本地列表
            moodEntries.insert(entry, at: 0)
            
            showConfirmation = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
            print("✅ 情绪日记保存成功")
        } catch {
            print("❌ 保存情绪日记失败: \(error)")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        
        isSaving = false
    }
    
    private func loadMoodHistory() async {
        guard let userId = authService.currentUser?.id else { return }
        
        isLoadingHistory = true
        
        do {
            // Let the Supabase SDK decode directly into our model
            let entries: [MoodDiaryEntry] = try await supabaseService.client
                .from("mood_entries")
                .select()
                .eq("user_id", value: userId)
                .order("created_at", ascending: false)
                .limit(50)
                .execute()
                .value
            
            moodEntries = entries
            print("✅ 加载了 \(moodEntries.count) 条情绪记录")
        } catch {
            print("❌ 加载情绪历史失败: \(error)")
        }
        
        isLoadingHistory = false
    }
    
    private func resetForm() {
        selectedMood = nil
        moodIntensity = 5.0
        moodNote = ""
    }
}

// MARK: - Mood Card Component

struct MoodCard: View {
    let mood: MoodType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 32))
                
                Text(mood.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if isSelected {
                        mood.color
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? mood.color : Color.clear,
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: isSelected ? mood.color.opacity(0.3) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - Mood History Card

struct MoodHistoryCard: View {
    let entry: MoodDiaryEntry
    
    private var moodType: MoodType? {
        MoodType.allCases.first { $0.rawValue == entry.mood }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 12) {
                    if let mood = moodType {
                        Text(mood.emoji)
                            .font(.title2)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mood.rawValue)
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text("强度: \(entry.intensity)/10")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entry.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            
            if let note = entry.note, !note.isEmpty {
                Text(note)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .padding(.top, 4)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    moodType?.color.opacity(0.3) ?? Color.clear,
                    lineWidth: 1
                )
        )
    }
}

#Preview {
    MoodDiaryView()
}
