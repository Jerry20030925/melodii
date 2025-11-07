//
//  CreativeComponents.swift
//  Melodii
//
//  创作页面的各种组件
//

import SwiftUI
import PhotosUI

// MARK: - 创作标签按钮

struct CreativeTabButton: View {
    let tab: CreativeTab
    let isSelected: Bool
    let hasContent: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Image(systemName: tab.icon)
                        .font(.system(size: 16, weight: .semibold))
                    
                    // 内容指示器
                    if hasContent && !isSelected {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                            .offset(x: 12, y: -12)
                    }
                }
                
                Text(tab.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(Capsule())
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: isSelected ? Color.blue.opacity(0.3) : Color.clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 创作工具按钮

struct CreativeToolButton: View {
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isActive ? color : Color(.systemGray5))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .stroke(
                                isActive ? color.opacity(0.3) : Color.clear,
                                lineWidth: 2
                            )
                    )
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isActive ? .white : .secondary)
                    .symbolEffect(.bounce, value: isActive)
                
                // 活跃指示器
                if isActive {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .offset(x: 14, y: -14)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)
    }
}

// MARK: - 增强文本编辑器

struct EnhancedTextEditor: View {
    @Binding var text: String
    @Binding var isEditorActive: Bool
    let mood: CreativeMood
    let template: CreativeTemplate?
    
    @State private var characterCount: Int = 0
    @State private var suggestions: [String] = []
    @FocusState private var isEditorFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 头部信息
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("分享你的想法")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    if let template = template {
                        Text("模板：\(template.name)")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }
                
                Spacer()
                
                // 字数统计
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(characterCount)/500")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(characterCount > 450 ? .red : .secondary)
                    
                    Text(mood.emoji)
                        .font(.title3)
                }
            }
            
            // 文本编辑器
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        isEditorFocused 
                                            ? mood.primaryColor.opacity(0.5) 
                                            : Color(.systemGray4), 
                                        lineWidth: 2
                                    )
                                    .animation(.easeInOut(duration: 0.2), value: isEditorFocused)
                            )
                    )
                    .frame(minHeight: 120)
                    .focused($isEditorFocused)
                    .onChange(of: text) { _, newValue in
                        characterCount = newValue.count
                        generateSuggestions(for: newValue)
                    }
                    .onChange(of: isEditorFocused) { _, focused in
                        isEditorActive = focused
                    }
                
                // 占位符
                if text.isEmpty {
                    Text(placeholderText)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .allowsHitTesting(false)
                }
            }
            
            // AI 写作建议
            if !suggestions.isEmpty && isEditorFocused {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion) {
                                insertSuggestion(suggestion)
                            }
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(mood.primaryColor.opacity(0.1))
                            .foregroundStyle(mood.primaryColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.8), value: suggestions)
            }
        }
    }
    
    private var placeholderText: String {
        if let template = template {
            return template.placeholder
        }
        
        switch mood {
        case .casual: return "随便聊聊今天发生的事..."
        case .artistic: return "用艺术的眼光描述你的感受..."
        case .professional: return "分享一些专业见解或经验..."
        case .playful: return "来个有趣的故事或笑话吧！"
        case .elegant: return "优雅地表达你的想法..."
        case .vibrant: return "充满活力地分享你的生活！"
        }
    }
    
    private func generateSuggestions(for text: String) {
        // 简化的建议生成逻辑
        guard !text.isEmpty else {
            suggestions = []
            return
        }
        
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        let lastWord = words.last ?? ""
        
        // 基于最后一个词生成建议
        var newSuggestions: [String] = []
        
        if lastWord.contains("今天") {
            newSuggestions = ["真的很棒", "让我印象深刻", "充满惊喜"]
        } else if lastWord.contains("感觉") {
            newSuggestions = ["很舒服", "有点特别", "难以形容"]
        } else if lastWord.contains("看到") {
            newSuggestions = ["美丽的风景", "有趣的事情", "特别的瞬间"]
        } else {
            newSuggestions = ["✨", "💭", "🌟", "继续写..."]
        }
        
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            suggestions = newSuggestions
        }
    }
    
    private func insertSuggestion(_ suggestion: String) {
        text += suggestion
        withAnimation {
            suggestions = []
        }
    }
}

// MARK: - 增强媒体区域

struct EnhancedMediaSection: View {
    @Binding var mediaURLs: [String]
    @Binding var pickerItems: [PhotosPickerItem]
    @Binding var appliedFilters: [ImageFilter]
    @Binding var isUploading: Bool
    @Binding var uploadProgress: Double
    @Binding var showFilterSelector: Bool
    
    let onPicked: ([PhotosPickerItem]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("媒体内容")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !mediaURLs.isEmpty {
                    Button("滤镜") {
                        showFilterSelector = true
                    }
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                
                if isUploading {
                    HStack(spacing: 8) {
                        ProgressView(value: uploadProgress)
                            .frame(width: 60)
                            .tint(.blue)
                        Text("\(Int(uploadProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.blue)
                    }
                }
            }
            
            // 媒体网格
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 12)
            ], spacing: 12) {
                ForEach(Array(mediaURLs.enumerated()), id: \.offset) { index, url in
                    EnhancedMediaThumbnail(
                        url: url,
                        filters: appliedFilters,
                        onRemove: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                _ = mediaURLs.remove(at: index)
                            }
                        }
                    )
                }
                
                // 添加媒体按钮
                if mediaURLs.count < 9 {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: 9 - mediaURLs.count,
                        matching: .any(of: [.images, .videos]),
                        photoLibrary: .shared()
                    ) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.blue)
                            
                            Text("添加")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .frame(height: 100)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 2, dash: [8]))
                        )
                    }
                    .onChange(of: pickerItems) { _, newItems in
                        if !newItems.isEmpty {
                            onPicked(newItems)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
}

// MARK: - 增强媒体缩略图

struct EnhancedMediaThumbnail: View {
    let url: String
    let filters: [ImageFilter]
    let onRemove: () -> Void
    
    @State private var showFullscreen = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: URL(string: url)) { image in
                image
                    .resizable()
                    .scaledToFill()
                    .applyFilters(filters) // 自定义修饰符
            } placeholder: {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
            .frame(height: 100)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                showFullscreen = true
            }
            
            // 删除按钮
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            .offset(x: -6, y: 6)
            
            // 滤镜指示器
            if !filters.isEmpty {
                HStack {
                    Image(systemName: "camera.filters")
                        .font(.caption)
                    Text("\(filters.count)")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .clipShape(Capsule())
                .offset(x: -8, y: 80)
            }
        }
        .sheet(isPresented: $showFullscreen) {
            MediaFullscreenView(url: url, filters: filters)
        }
    }
}

// MARK: - 智能标签建议

struct SmartTagSuggestions: View {
    let text: String
    @Binding var selectedTags: [String]
    @Binding var moodTags: [String]
    
    @State private var suggestedTags: [String] = []
    @State private var suggestedMoodTags: [String] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !suggestedTags.isEmpty || !suggestedMoodTags.isEmpty {
                Text("智能标签推荐")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                // 话题标签
                if !suggestedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("话题标签")
                            .font(.caption)
                            .foregroundStyle(.blue)
                        
                        TagCloud(
                            tags: suggestedTags,
                            selectedTags: $selectedTags,
                            style: .topic
                        )
                    }
                }
                
                // 心情标签
                if !suggestedMoodTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("心情标签")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        
                        TagCloud(
                            tags: suggestedMoodTags,
                            selectedTags: $moodTags,
                            style: .mood
                        )
                    }
                }
            }
        }
        .onChange(of: text) { _, newText in
            generateSmartTags(for: newText)
        }
        .onAppear {
            generateSmartTags(for: text)
        }
    }
    
    private func generateSmartTags(for text: String) {
        guard !text.isEmpty else {
            suggestedTags = []
            suggestedMoodTags = []
            return
        }
        
        // 简化的智能标签生成
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines)
        
        var topics: [String] = []
        var moods: [String] = []
        
        // 基于关键词推荐话题标签
        if words.contains(where: { $0.contains("咖啡") || $0.contains("coffee") }) {
            topics.append("咖啡时光")
        }
        if words.contains(where: { $0.contains("旅行") || $0.contains("旅游") }) {
            topics.append("旅行日记")
        }
        if words.contains(where: { $0.contains("读书") || $0.contains("书") }) {
            topics.append("读书笔记")
        }
        if words.contains(where: { $0.contains("音乐") || $0.contains("歌") }) {
            topics.append("音乐分享")
        }
        
        // 基于情感词推荐心情标签
        if words.contains(where: { $0.contains("开心") || $0.contains("快乐") }) {
            moods.append("😊 开心")
        }
        if words.contains(where: { $0.contains("累") || $0.contains("疲惫") }) {
            moods.append("😴 疲惫")
        }
        if words.contains(where: { $0.contains("兴奋") || $0.contains("激动") }) {
            moods.append("🎉 兴奋")
        }
        if words.contains(where: { $0.contains("平静") || $0.contains("安静") }) {
            moods.append("🧘 平静")
        }
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            suggestedTags = topics
            suggestedMoodTags = moods
        }
    }
}

// MARK: - 标签云

struct TagCloud: View {
    let tags: [String]
    @Binding var selectedTags: [String]
    let style: TagStyle
    
    enum TagStyle {
        case topic, mood
        
        var color: Color {
            switch self {
            case .topic: return .blue
            case .mood: return .orange
            }
        }
    }
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 60), spacing: 8)
        ], spacing: 8) {
            ForEach(tags, id: \.self) { tag in
                TagButton(
                    tag: tag,
                    isSelected: selectedTags.contains(tag),
                    color: style.color
                ) {
                    toggleTag(tag)
                }
            }
        }
    }
    
    private func toggleTag(_ tag: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            if selectedTags.contains(tag) {
                selectedTags.removeAll { $0 == tag }
            } else {
                selectedTags.append(tag)
            }
        }
    }
}

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(tag)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? .white : color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? color : color.opacity(0.15))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(color.opacity(isSelected ? 0 : 0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isSelected ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

// MARK: - 背景装饰元素

struct CreativeBackgroundElements: View {
    let mood: CreativeMood
    
    var body: some View {
        ZStack {
            // 浮动圆点
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                mood.primaryColor.opacity(0.3),
                                mood.secondaryColor.opacity(0.1),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 60, height: 60)
                    .offset(
                        x: CGFloat.random(in: -200...200),
                        y: CGFloat.random(in: -300...300)
                    )
                    .animation(
                        .easeInOut(duration: Double.random(in: 3...6))
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.5),
                        value: mood
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 自定义修饰符

extension View {
    func applyFilters(_ filters: [ImageFilter]) -> some View {
        // 这里应该实现实际的滤镜效果
        // 现在只是示例代码
        self.overlay(
            filters.isEmpty ? nil :
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            filters.first?.color.opacity(0.2) ?? Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }
}

// MARK: - 滤镜数据

struct ImageFilter: Identifiable {
    let id = UUID()
    let name: String
    let intensity: Double
    let color: Color
    
    static let presets: [ImageFilter] = [
        ImageFilter(name: "暖色调", intensity: 0.3, color: .orange),
        ImageFilter(name: "冷色调", intensity: 0.3, color: .blue),
        ImageFilter(name: "复古", intensity: 0.4, color: .brown),
        ImageFilter(name: "鲜艳", intensity: 0.5, color: .red),
        ImageFilter(name: "柔和", intensity: 0.2, color: .pink)
    ]
}

// MARK: - 创作模板

struct CreativeTemplate: Identifiable {
    let id = UUID()
    let name: String
    let category: String
    let placeholder: String
    let suggestedTags: [String]
    let mood: CreativeMood
    
    static let presets: [CreativeTemplate] = [
        CreativeTemplate(
            name: "日常分享",
            category: "生活",
            placeholder: "分享一下今天的日常生活...",
            suggestedTags: ["日常", "生活", "记录"],
            mood: .casual
        ),
        CreativeTemplate(
            name: "旅行游记",
            category: "旅行",
            placeholder: "记录这次旅行的美好时光...",
            suggestedTags: ["旅行", "风景", "记忆"],
            mood: .vibrant
        ),
        CreativeTemplate(
            name: "美食分享",
            category: "美食",
            placeholder: "这道美食太棒了，必须分享...",
            suggestedTags: ["美食", "料理", "美味"],
            mood: .playful
        ),
        CreativeTemplate(
            name: "艺术创作",
            category: "艺术",
            placeholder: "展示我的创作作品...",
            suggestedTags: ["艺术", "创作", "灵感"],
            mood: .artistic
        )
    ]
}

#Preview {
    VStack {
        CreativeTabButton(
            tab: .content,
            isSelected: true,
            hasContent: true
        ) { }
        
        CreativeToolButton(
            icon: "music.note",
            isActive: true,
            color: .blue
        ) { }
    }
    .padding()
}