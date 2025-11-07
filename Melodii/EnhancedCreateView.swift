//
//  EnhancedCreateView.swift
//  Melodii
//
//  增强的创作页面：专业模板、音乐配乐、智能滤镜
//

import SwiftUI
import Combine
import PhotosUI
import AVFoundation
import UIKit

struct EnhancedCreateView: View {
    // 外部传入：草稿（可选）
    let draftPost: Post?
    
    // 依赖服务
    @ObservedObject private var authService = AuthService.shared
    @StateObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var locationService = LocationService.shared
    
    // 基础表单状态
    @State private var text: String = ""
    @State private var mediaURLs: [String] = []
    @State private var topics: [String] = []
    @State private var moodTags: [String] = []
    
    // 新增：音乐和模板状态
    @State private var selectedMusic: MusicRecommendation?
    @State private var selectedTemplate: CreativeTemplate?
    @State private var selectedMood: CreativeMood = .casual
    @State private var appliedFilters: [ImageFilter] = []
    
    // 选项区状态
    @State private var city: String = ""
    @State private var isAnonymous: Bool = false
    
    // UI 状态
    @State private var isSubmitting: Bool = false
    @State private var publishProgress: Double = 0.0
    @State private var publishStep: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showLocationPermissionAlert: Bool = false
    
    // 新增：专业创作 UI 状态
    @State private var showMusicSelector = false
    @State private var showTemplateSelector = false
    @State private var showMoodSelector = false
    @State private var showFilterSelector = false
    @State private var isPreviewMode = false
    @State private var currentCreativeTab: CreativeTab = .content
    
    // 媒体选择/上传
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadingCount: Int = 0
    @State private var totalUploadCount: Int = 0
    
    // 键盘控制
    @FocusState private var isTextEditorFocused: Bool
    @State private var isEditorActive: Bool = false
    
    init(draftPost: Post?) {
        self.draftPost = draftPost
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundView
                
                VStack(spacing: 0) {
                    // 创作模式切换栏
                    creativeTabBar
                    
                    // 内容区域
                    ScrollView {
                        VStack(spacing: 24) {
                            switch currentCreativeTab {
                            case .content:
                                contentSection
                            case .design:
                                designSection
                            case .music:
                                musicSection
                            case .preview:
                                previewSection
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 100) // 为底部操作栏留空间
                    }
                }
                
                // 底部创作工具栏
                VStack {
                    Spacer()
                    creativeToolbar
                }
                .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .navigationTitle(draftPost == nil ? "创作" : "编辑草稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        // 处理取消逻辑
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("发布")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(isSubmitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaURLs.isEmpty))
                }
            }
            .sheet(isPresented: $showMusicSelector) {
                MusicSelectorSheet(selectedMusic: $selectedMusic)
            }
            .sheet(isPresented: $showTemplateSelector) {
                TemplateSelectorSheet(selectedTemplate: $selectedTemplate)
            }
            .task {
                if let draft = draftPost {
                    loadDraftData(draft)
                }
            }
        }
    }
    
    // MARK: - 背景视图
    
    private var backgroundView: some View {
        ZStack {
            // 基础渐变背景
            LinearGradient(
                colors: [
                    selectedMood.primaryColor.opacity(0.1),
                    selectedMood.secondaryColor.opacity(0.05),
                    Color(.systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: selectedMood)
            
            // 浮动装饰元素
            CreativeBackgroundElements(mood: selectedMood)
        }
    }
    
    // MARK: - 创作标签栏
    
    private var creativeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(CreativeTab.allCases, id: \.self) { tab in
                    CreativeTabButton(
                        tab: tab,
                        isSelected: currentCreativeTab == tab,
                        hasContent: tabHasContent(tab)
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            currentCreativeTab = tab
                            isTextEditorFocused = false
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - 内容部分
    
    private var contentSection: some View {
        VStack(spacing: 24) {
            // 文本输入区域 - 增强版
            EnhancedTextEditor(
                text: $text,
                isEditorActive: $isEditorActive,
                mood: selectedMood,
                template: selectedTemplate
            )
            
            // 媒体部分 - 带滤镜预览
            if !mediaURLs.isEmpty || !pickerItems.isEmpty {
                EnhancedMediaSection(
                    mediaURLs: $mediaURLs,
                    pickerItems: $pickerItems,
                    appliedFilters: $appliedFilters,
                    isUploading: $isUploading,
                    uploadProgress: $uploadProgress,
                    showFilterSelector: $showFilterSelector
                ) { items in
                    Task { await handlePickedItems(items) }
                }
            }
            
            // 智能标签建议
            SmartTagSuggestions(
                text: text,
                selectedTags: $topics,
                moodTags: $moodTags
            )
        }
    }
    
    // MARK: - 设计部分
    
    private var designSection: some View {
        VStack(spacing: 24) {
            // 模板选择
            TemplateSelectionSection(
                selectedTemplate: $selectedTemplate,
                showTemplateSelector: $showTemplateSelector
            )
            
            // 心情模式
            MoodSelectionSection(
                selectedMood: $selectedMood
            )
            
            // 滤镜效果
            FilterSelectionSection(
                appliedFilters: $appliedFilters,
                showFilterSelector: $showFilterSelector
            )
        }
    }
    
    // MARK: - 音乐部分
    
    private var musicSection: some View {
        VStack(spacing: 24) {
            MusicSelectionSection(
                selectedMusic: $selectedMusic,
                showMusicSelector: $showMusicSelector
            )
        }
    }
    
    // MARK: - 预览部分
    
    private var previewSection: some View {
        VStack(spacing: 24) {
            Text("预览效果")
                .font(.title3)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 帖子预览卡片
            PostPreviewCard(
                text: text,
                mediaURLs: mediaURLs,
                selectedMusic: selectedMusic,
                selectedTemplate: selectedTemplate,
                appliedFilters: appliedFilters,
                mood: selectedMood,
                author: authService.currentUser ?? User(id: "preview", nickname: "预览用户"),
                isAnonymous: isAnonymous
            )
            
            // 预览操作
            HStack(spacing: 16) {
                Button("3D预览") {
                    // 3D预览
                }
                .buttonStyle(.bordered)
                
                Button("AR预览") {
                    // AR预览
                }
                .buttonStyle(.bordered)
                
                Spacer()
            }
        }
    }
    
    // MARK: - 创作工具栏
    
    private var creativeToolbar: some View {
        HStack {
            // 快速操作按钮
            HStack(spacing: 20) {
                CreativeToolButton(
                    icon: "music.note",
                    isActive: selectedMusic != nil,
                    color: .blue
                ) {
                    showMusicSelector = true
                }
                
                CreativeToolButton(
                    icon: "wand.and.stars",
                    isActive: selectedTemplate != nil,
                    color: .purple
                ) {
                    showTemplateSelector = true
                }
                
                CreativeToolButton(
                    icon: "camera.filters",
                    isActive: !appliedFilters.isEmpty,
                    color: .orange
                ) {
                    showFilterSelector = true
                }
                
                CreativeToolButton(
                    icon: "location",
                    isActive: !city.isEmpty,
                    color: .green
                ) {
                    requestLocation()
                }
            }
            
            Spacer()
            
            // 发布按钮
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    } else {
                        Image(systemName: "paperplane.fill")
                        Text("发布")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [selectedMood.primaryColor, selectedMood.secondaryColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(Capsule())
                .shadow(color: selectedMood.primaryColor.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(isSubmitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaURLs.isEmpty))
        }
        .padding(20)
        .background(.ultraThinMaterial)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color(.systemGray4)),
            alignment: .top
        )
    }
    
    // MARK: - 辅助方法
    
    private func tabHasContent(_ tab: CreativeTab) -> Bool {
        switch tab {
        case .content: return !text.isEmpty || !mediaURLs.isEmpty
        case .design: return selectedTemplate != nil || !appliedFilters.isEmpty
        case .music: return selectedMusic != nil
        case .preview: return !text.isEmpty || !mediaURLs.isEmpty
        }
    }
    
    private func loadDraftData(_ draft: Post) {
        text = draft.text ?? ""
        mediaURLs = draft.mediaURLs
        topics = draft.topics
        moodTags = draft.moodTags
        city = draft.city ?? ""
        isAnonymous = draft.isAnonymous
    }
    
    private func requestLocation() {
        guard !locationService.isLocating else { return }
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        withAnimation(.easeOut(duration: 0.2)) {
            city = ""
        }
        
        locationService.currentCity = nil
        locationService.locationError = nil
        locationService.requestCity()
    }
    
    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        // 与原版CreateView相同的上传逻辑
        guard let userId = authService.currentUser?.id else { return }
        
        isUploading = true
        uploadProgress = 0.0
        uploadingCount = 0
        totalUploadCount = items.count
        
        defer { 
            isUploading = false
            uploadProgress = 0.0
            uploadingCount = 0
            totalUploadCount = 0
            pickerItems = []
        }

        var newURLs: [String] = []
        
        for (index, item) in items.enumerated() {
            uploadingCount = index + 1
            
            do {
                // 简化的上传逻辑（实际应用中需要完整实现）
                if let data = try await item.loadTransferable(type: Data.self) {
                    let url = try await supabaseService.uploadPostMediaWithProgress(
                        data: data,
                        mime: "image/jpeg",
                        fileName: nil,
                        folder: "posts/\(userId)/enhanced",
                        bucket: "media",
                        isPublic: true,
                        onProgress: { progress in
                            Task { await updateUploadProgress(Double(index) / Double(totalUploadCount) + progress / Double(totalUploadCount)) }
                        }
                    )
                    
                    newURLs.append(url)
                    await MainActor.run {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            mediaURLs.append(url)
                        }
                    }
                }
            } catch {
                alertMessage = "上传失败：\(error.localizedDescription)"
                showAlert = true
            }
        }
    }
    
    @MainActor
    private func updateUploadProgress(_ progress: Double) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            uploadProgress = progress
        }
    }
    
    private func submit() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        publishProgress = 0.0
        publishStep = "准备发布..."
        isSubmitting = true
        
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        defer { 
            isSubmitting = false
            publishProgress = 0.0
            publishStep = ""
        }

        do {
            await updateProgress(0.2, "处理创作内容...")
            
            // 创建帖子数据
            await updateProgress(0.5, "发布创作...")
            
            let post = try await supabaseService.createPost(
                authorId: authService.currentUser!.id,
                text: text.isEmpty ? nil : text,
                mediaURLs: mediaURLs,
                topics: topics,
                moodTags: moodTags,
                city: city.isEmpty ? nil : city,
                isAnonymous: isAnonymous
            )
            
            await updateProgress(1.0, "发布成功！")
            try await Task.sleep(nanoseconds: 500_000_000)
            
            // 清空表单
            resetForm()
            
            alertMessage = "发布成功！你的创作已经与大家分享"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
        } catch {
            await updateProgress(0.0, "发布失败")
            alertMessage = "发布失败：\(error.localizedDescription)"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    private func resetForm() {
        text = ""
        mediaURLs = []
        topics = []
        moodTags = []
        selectedMusic = nil
        selectedTemplate = nil
        appliedFilters = []
        city = ""
        isAnonymous = false
        selectedMood = .casual
    }
    
    @MainActor
    private func updateProgress(_ progress: Double, _ step: String) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            publishProgress = progress
            publishStep = step
        }
    }
}

// MARK: - 创作标签页

enum CreativeTab: String, CaseIterable {
    case content = "内容"
    case design = "设计"
    case music = "音乐"
    case preview = "预览"
    
    var icon: String {
        switch self {
        case .content: return "square.and.pencil"
        case .design: return "paintbrush.pointed"
        case .music: return "music.note"
        case .preview: return "eye"
        }
    }
}

// MARK: - 创作心情

enum CreativeMood: String, CaseIterable {
    case casual = "随性"
    case artistic = "艺术"
    case professional = "专业"
    case playful = "趣味"
    case elegant = "优雅"
    case vibrant = "活力"
    
    var primaryColor: Color {
        switch self {
        case .casual: return .blue
        case .artistic: return .purple
        case .professional: return .gray
        case .playful: return .orange
        case .elegant: return .pink
        case .vibrant: return .green
        }
    }
    
    var secondaryColor: Color {
        switch self {
        case .casual: return .cyan
        case .artistic: return .indigo
        case .professional: return .black
        case .playful: return .yellow
        case .elegant: return .purple
        case .vibrant: return .mint
        }
    }
    
    var emoji: String {
        switch self {
        case .casual: return "😌"
        case .artistic: return "🎨"
        case .professional: return "💼"
        case .playful: return "🎪"
        case .elegant: return "✨"
        case .vibrant: return "🌈"
        }
    }
}

// MARK: - 增强帖子数据

struct EnhancedPostData {
    let text: String
    let mediaURLs: [String]
    let musicURL: String?
    let templateId: String?
    let filters: [String]
    let mood: String
    let topics: [String]
    let moodTags: [String]
    let city: String?
    let isAnonymous: Bool
}

#Preview {
    EnhancedCreateView(draftPost: nil)
}