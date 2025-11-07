//
//  CreateView.swift
//  Melodii
//
//  发布页：支持从草稿进入编辑，定位城市、匿名发布选项；新增图片/视频选择与上传
//

import SwiftUI
import Combine
import PhotosUI
import AVFoundation
import UIKit

enum CreateMode: Hashable {
    case post
    case melomoment
}

struct CreateView: View {
    // 外部传入：草稿（可选）
    let draftPost: Post?
    let initialMode: CreateMode

    // 依赖服务
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var locationService = LocationService.shared

    // 表单状态
    @State private var text: String = ""
    @State private var mediaURLs: [String] = []         // 已上传成功的媒体URL（图片/视频混合）
    @State private var topics: [String] = []
    @State private var moodTags: [String] = []
    
    // 音乐选择
    @State private var selectedMusic: MusicRecommendation?
    @State private var showMusicSelector = false

    // 选项区状态
    @State private var city: String = ""
    @State private var isAnonymous: Bool = false

    // 其它 UI 状态
    @State private var isSubmitting: Bool = false
    @State private var publishProgress: Double = 0.0
    @State private var publishStep: String = ""
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @State private var showLocationPermissionAlert: Bool = false

    // 媒体选择/上传
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading: Bool = false
    @State private var uploadProgress: Double = 0.0
    @State private var uploadingCount: Int = 0
    @State private var totalUploadCount: Int = 0
    
    // Melomoment 上传（迁移到创作页）
    @State private var melomomentItem: PhotosPickerItem? = nil
    @State private var isUploadingMoment: Bool = false
    @State private var addRippleProgress: CGFloat = 0
    @State private var showAddRipple: Bool = false

    // 上传体积阈值（根据 Supabase Storage 典型限制做保守设置）
    private let maxImageBytes: Int = 4 * 1024 * 1024     // 4MB
    private let maxVideoBytes: Int = 25 * 1024 * 1024    // 25MB（超过则提示压缩/截取）

    // 全屏预览
    @State private var showViewer = false
    @State private var viewerIndex = 0

    // 键盘控制
    @FocusState private var isTextEditorFocused: Bool

    // Extracted grid columns to reduce type-checking complexity
    private static let mediaGridColumns: [GridItem] = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    @State private var createMode: CreateMode = .post

    init(draftPost: Post?, initialMode: CreateMode = .post) {
        self.draftPost = draftPost
        self.initialMode = initialMode
        _createMode = State(initialValue: initialMode)
    }
    
    // MARK: - Background gradient extraction
    
    private var backgroundGradientColors: [Color] {
        let base = Color(.systemGroupedBackground)
        let tail = Color(.systemBackground)
        // compute a soft tint from selected music category if available
        let tint: Color = {
            guard let music = selectedMusic else { return base }
            // category.gradient returns [Color]; use first if present
            if let first = music.category.gradient.first {
                return first.opacity(0.05)
            }
            return base
        }()
        return [base, tint, tail]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // 动态渐变背景（extracted colors to help type checker）
                LinearGradient(
                    colors: backgroundGradientColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.8), value: selectedMusic?.id)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // 创作类型切换
                        Picker("创作类型", selection: $createMode) {
                            Text("发帖").tag(CreateMode.post)
                            Text("Melomoment").tag(CreateMode.melomoment)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        
                        // 当选择 Melomoment 时，显示专属上传区；否则显示发帖内容区
                        if createMode == .melomoment {
                            melomomentCreateSection
                        }
                        
                        // 文本输入区域（仅发帖模式显示）
                        if createMode == .post {
                            postTextSection
                        }

                    // 发帖模式内容
                    if createMode == .post {
                        // 媒体部分
                        if !mediaURLs.isEmpty || !isUploading {
                        mediaSection
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    
                        // 音乐选择区域
                        MusicSelectionSection(
                            selectedMusic: $selectedMusic,
                            showMusicSelector: $showMusicSelector
                        )
                        .scaleEffect(selectedMusic != nil ? 1.02 : 1.0)
                        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: selectedMusic?.id)

                        // 选项区（定位 + 匿名）
                        optionsSection

                        // 话题与标签
                        if !topics.isEmpty || !moodTags.isEmpty {
                            tagsSection
                        }
                    
                            // 底部间距
                            Spacer(minLength: 100)
                    }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 20)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTextEditorFocused = false
            }
            .navigationTitle(draftPost == nil ? "发布" : "编辑草稿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button {
                            isTextEditorFocused = false
                        } label: {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if createMode == .post {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text(draftPost == nil ? "发布" : "更新")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isSubmitting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && mediaURLs.isEmpty))
                    }
                }
            }
            .task {
                if let draft = draftPost {
                    text = draft.text ?? ""
                    mediaURLs = draft.mediaURLs
                    topics = draft.topics
                    moodTags = draft.moodTags
                    city = draft.city ?? ""
                    isAnonymous = draft.isAnonymous
                    // TODO: 加载草稿的音乐选择
                }
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .alert("需要位置权限", isPresented: $showLocationPermissionAlert) {
                Button("取消", role: .cancel) {}
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text("请在系统设置中允许Melodii访问您的位置信息")
            }
            .sheet(isPresented: $showViewer) {
                FullscreenMediaViewer(urls: mediaURLs, isPresented: $showViewer, index: viewerIndex)
            }
            .sheet(isPresented: $showMusicSelector) {
                MusicSelectorSheet(selectedMusic: $selectedMusic)
            }
            .overlay(
                // 发布进度覆盖层
                publishProgressOverlay
            )
            .onChange(of: locationService.currentCity) { oldValue, newValue in
                // 当获取到城市信息时，更新city状态并显示动画
                if let newCity = newValue, !newCity.isEmpty {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                        city = newCity
                    }
                    // 成功反馈
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
            .onChange(of: locationService.locationError) { oldValue, newValue in
                // 当出现位置错误时，显示提示
                if let error = newValue, !error.isEmpty {
                    // 只在明确是权限被拒绝时才显示权限提示
                    // 不在超时或网络错误时显示权限提示
                    if error.contains("权限未授权") || error.contains("请在设置中开启") {
                        // 再次确认权限状态，避免误判
                        let status = locationService.authorizationStatus
                        if status == .denied || status == .restricted {
                            showLocationPermissionAlert = true
                        } else {
                            // 权限实际上是允许的，只是定位失败了
                            alertMessage = error
                            showAlert = true
                        }
                    } else {
                        // 其他错误（超时、网络等）直接显示
                        alertMessage = error
                        showAlert = true
                    }
                    // 错误反馈
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
            .onChange(of: melomomentItem) { oldValue, newValue in
                Task { await handlePickMelomomentFromCreate(newValue) }
            }
        }
    }
    
    // MARK: - 抽出文本输入区域，降低 body 复杂度
    @ViewBuilder
    private var postTextSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("内容")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                Text("\(text.count)/500")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(text.count > 450 ? .red : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(text.count > 450 ? Color.red.opacity(0.1) : Color(.systemGray6))
                    )
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: text.count)
            }
        
            TextEditor(text: $text)
                .frame(minHeight: 180)
                .padding(20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(.systemBackground))
                        
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isTextEditorFocused ?
                                    LinearGradient(
                                        colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ) :
                                    LinearGradient(
                                        colors: [Color(.systemGray4), Color(.systemGray4)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                lineWidth: isTextEditorFocused ? 2 : 1
                            )
                        
                        if isTextEditorFocused {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.03), .purple.opacity(0.03)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                    }
                )
                .overlay(
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("分享你的想法、心情或有趣的事情...")
                                    .font(.body)
                                    .foregroundStyle(.tertiary)
                                
                                HStack(spacing: 4) {
                                    Text("💭")
                                    Text("记录此刻的美好")
                                        .font(.caption)
                                        .foregroundStyle(.quaternary)
                                }
                            }
                            .padding(.horizontal, 28)
                            .padding(.vertical, 28)
                            .allowsHitTesting(false)
                            .opacity(isTextEditorFocused ? 0.6 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isTextEditorFocused)
                        }
                    }
                )
                .focused($isTextEditorFocused)
                .scrollContentBackground(.hidden)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isTextEditorFocused)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .scaleEffect(isTextEditorFocused ? 1.01 : 1.0)
        .shadow(
            color: isTextEditorFocused ? Color.blue.opacity(0.1) : .clear,
            radius: isTextEditorFocused ? 12 : 0,
            x: 0,
            y: isTextEditorFocused ? 6 : 0
        )
    }
    
    // MARK: - Progress Overlay
    
    @ViewBuilder
    private var publishProgressOverlay: some View {
        if isSubmitting {
            ZStack {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 24) {
                    // 进度圆环
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 8)
                            .frame(width: 80, height: 80)
                        
                        Circle()
                            .trim(from: 0, to: publishProgress)
                            .stroke(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                style: StrokeStyle(lineWidth: 8, lineCap: .round)
                            )
                            .frame(width: 80, height: 80)
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut(duration: 0.5), value: publishProgress)
                        
                        Text("\(Int(publishProgress * 100))%")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                    }
                    
                    VStack(spacing: 8) {
                        Text("正在发布...")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                        
                        Text(publishStep)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(40)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .scaleEffect(isSubmitting ? 1.0 : 0.8)
                .opacity(isSubmitting ? 1.0 : 0.0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isSubmitting)
            }
            .transition(.opacity)
        }
    }

    // MARK: - 媒体区域

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    Text("媒体")
                        .font(.headline)
                        .fontWeight(.semibold)
                }
                
                Spacer()
                
                if isUploading {
                    VStack(spacing: 4) {
                        HStack(spacing: 8) {
                            ProgressView(value: uploadProgress)
                                .frame(width: 60)
                                .tint(.orange)
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(.orange)
                        }
                        Text("上传中 \(uploadingCount)/\(totalUploadCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if !mediaURLs.isEmpty {
                    Text("\(mediaURLs.count)/9")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .clipShape(Capsule())
                }
            }

            LazyVGrid(columns: Self.mediaGridColumns, spacing: 12) {
                ForEach(Array(mediaURLs.enumerated()), id: \.offset) { pair in
                    let idx = pair.offset
                    let url = pair.element

                    MediaGridItem(
                        url: url,
                        onTap: {
                            viewerIndex = idx
                            showViewer = true
                        },
                        onRemove: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if idx < mediaURLs.count && mediaURLs[idx] == url {
                                    mediaURLs.remove(at: idx)
                                } else if let currentIndex = mediaURLs.firstIndex(of: url) {
                                    mediaURLs.remove(at: currentIndex)
                                }
                            }
                        }
                    )
                }

                // 添加媒体按钮
                if mediaURLs.count < 9 {
                    MediaPickerTile(
                        selection: $pickerItems,
                        onPicked: { items in
                            Task { await handlePickedItems(items) }
                        }
                    )
                }
            }
        }
        .padding(20)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(.systemBackground))
                
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [Color.orange.opacity(0.3), Color.pink.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.5
                    )
            }
        )
        .shadow(
            color: Color.orange.opacity(0.1),
            radius: 8, x: 0, y: 4
        )
    }

    // MARK: - Melomoment 专属上传区（同款渐变环 + 涟漪）
    private var melomomentCreateSection: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Melomoment")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Text("分享此刻")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .opacity(0.8)
                }
                Spacer()
                PhotosPicker(selection: $melomomentItem, matching: .images) {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [.pink, .orange, .purple, .blue, .cyan, .pink],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(270)
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Circle()
                                        .trim(from: 0, to: addRippleProgress)
                                        .stroke(
                                            AngularGradient(
                                                colors: [.pink.opacity(0.6), .purple.opacity(0.6), .orange.opacity(0.6)],
                                                center: .center
                                            ),
                                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                        )
                                        .frame(width: 40, height: 40)
                                        .rotationEffect(.degrees(-90))
                                        .opacity(showAddRipple ? 1 : 0)
                                )
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 28, height: 28)
                                .shadow(color: .pink.opacity(0.4), radius: 6, x: 0, y: 2)
                                .overlay(
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                )
                        }
                        Text("添加")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.pink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.pink.opacity(0.15),
                                                Color.orange.opacity(0.15)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.purple.opacity(0.3), .pink.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .shadow(color: .purple.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                .onTapGesture {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    showAddRipple = true
                    addRippleProgress = 0
                    withAnimation(.easeOut(duration: 0.6)) { addRippleProgress = 1 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showAddRipple = false
                        addRippleProgress = 0
                    }
                }
                .accessibilityLabel("添加 Melomoment")
            }

            VStack(spacing: 8) {
                Text("选择一张照片，我们将直接发布为 Melomoment")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if isUploadingMoment {
                    ProgressView("正在上传…")
                        .tint(.pink)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: [.purple.opacity(0.25), .pink.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Melomoment 上传处理（创作页）
    private func handlePickMelomomentFromCreate(_ item: PhotosPickerItem?) async {
        guard !isUploadingMoment, let item else { return }
        guard let me = authService.currentUser?.id else { return }
        isUploadingMoment = true
        defer { isUploadingMoment = false }

        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                let mime = "image/jpeg"
                let url = try await supabaseService.uploadUserMedia(
                    data: data,
                    mime: mime,
                    fileName: nil,
                    folder: "moments/\(me)"
                )

                _ = try await supabaseService.createMoment(
                    authorId: me,
                    mediaURL: url,
                    caption: nil
                )

                await MainActor.run {
                    alertMessage = "Melomoment 发布成功"
                    showAlert = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        } catch {
            await MainActor.run {
                alertMessage = "上传失败，请稍后重试"
                showAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    // MARK: - 选项区（定位 + 匿名）

    private var optionsSection: some View {
        VStack(spacing: 20) {
            // 定位按钮
            Button {
                requestLocation()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: city.isEmpty ? 
                                        [.green.opacity(0.15), .mint.opacity(0.15)] :
                                        [.green.opacity(0.25), .mint.opacity(0.25)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(city.isEmpty ? Color.clear : Color.green.opacity(0.3), lineWidth: 2)
                            )

                        if locationService.isLocating {
                            ProgressView()
                                .tint(.green)
                                .scaleEffect(0.9)
                        } else {
                            Image(systemName: city.isEmpty ? "location" : "location.fill")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.green)
                                .symbolEffect(.pulse, value: locationService.isLocating)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(city.isEmpty ? "添加位置" : city)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            if !city.isEmpty && !locationService.isLocating {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        
                        Text(locationService.isLocating ? "正在获取位置信息..." :
                             (city.isEmpty ? "点击获取当前位置" : "点击重新定位"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    if !city.isEmpty && !locationService.isLocating {
                        Button {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                city = ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(city.isEmpty ? Color(.systemGray6) : Color.green.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    city.isEmpty ? Color.clear : Color.green.opacity(0.2), 
                                    lineWidth: 1.5
                                )
                        )
                )
                .scaleEffect(locationService.isLocating ? 1.02 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: city)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: locationService.isLocating)
            }
            .disabled(locationService.isLocating)
            .buttonStyle(.plain)

            // 匿名发布开关
            Toggle(isOn: $isAnonymous) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: isAnonymous ? 
                                        [.purple.opacity(0.25), .indigo.opacity(0.25)] :
                                        [.gray.opacity(0.15), .gray.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                            .overlay(
                                Circle()
                                    .stroke(isAnonymous ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 2)
                            )
                        
                        Image(systemName: isAnonymous ? "person.fill.questionmark" : "person.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isAnonymous ? .purple : .secondary)
                            .symbolEffect(.bounce, value: isAnonymous)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("匿名发布")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            if isAnonymous {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.purple)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        
                        Text(isAnonymous ? "已启用匿名模式，将隐藏个人信息" : "隐藏你的个人信息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .tint(.purple)
            .padding(18)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isAnonymous ? Color.purple.opacity(0.06) : Color(.systemGray6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                isAnonymous ? Color.purple.opacity(0.2) : Color.clear, 
                                lineWidth: 1.5
                            )
                    )
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isAnonymous)
        }
    }

    // MARK: - 话题/标签占位

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("话题与标签")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if topics.isEmpty && moodTags.isEmpty {
                Text("可在此添加 #话题 或 情绪标签")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                HStack {
                    ForEach(topics, id: \.self) { t in
                        Text("#\(t)")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    ForEach(moodTags, id: \.self) { m in
                        Text(m)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    // MARK: - Location Functions
    
    private func requestLocation() {
        guard !locationService.isLocating else { return }

        // 添加触觉反馈
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // 清空当前城市和错误
        withAnimation(.easeOut(duration: 0.2)) {
            city = ""
        }

        // 清除旧的位置信息
        locationService.currentCity = nil
        locationService.locationError = nil

        // 请求定位
        locationService.requestCity()
    }

    private func submit() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        // 重置进度
        publishProgress = 0.0
        publishStep = "准备发布..."
        isSubmitting = true
        
        // 添加触觉反馈
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        
        defer { 
            isSubmitting = false
            publishProgress = 0.0
            publishStep = ""
        }

        do {
            if let draft = draftPost {
                // 更新草稿流程
                await updateProgress(0.2, "验证内容...")
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms
                
                await updateProgress(0.5, "更新草稿...")
                try await supabaseService.updatePostFull(
                    id: draft.id,
                    text: text,
                    topics: topics,
                    moodTags: moodTags,
                    city: city.isEmpty ? nil : city,
                    isAnonymous: isAnonymous,
                    mediaURLs: mediaURLs,
                    status: PostStatus.published
                )
                
                await updateProgress(1.0, "更新完成！")
                try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                
                alertMessage = "草稿已成功发布！"
                showAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } else {
                // 新发布流程
                await updateProgress(0.1, "验证内容...")
                try await Task.sleep(nanoseconds: 300_000_000)
                
                await updateProgress(0.3, "处理媒体文件...")
                try await Task.sleep(nanoseconds: 400_000_000)
                
                await updateProgress(0.6, "创建帖子...")
                _ = try await supabaseService.createPost(
                    authorId: userId,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaURLs: mediaURLs,
                    topics: topics,
                    moodTags: moodTags,
                    city: city.isEmpty ? nil : city,
                    isAnonymous: isAnonymous
                )
                
                await updateProgress(0.9, "同步数据...")
                try await Task.sleep(nanoseconds: 300_000_000)
                
                await updateProgress(1.0, "发布成功！")
                try await Task.sleep(nanoseconds: 500_000_000)
                
                // 清空表单
                text = ""
                mediaURLs = []
                topics = []
                moodTags = []
                city = ""
                isAnonymous = false
                selectedMusic = nil
                
                alertMessage = "发布成功！你的动态已经发布到社区"
                showAlert = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            await updateProgress(0.0, "发布失败")
            alertMessage = "发布失败：\(error.localizedDescription)"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    
    // MARK: - Progress Helper
    
    @MainActor
    private func updateProgress(_ progress: Double, _ step: String) async {
        withAnimation(.easeInOut(duration: 0.3)) {
            publishProgress = progress
            publishStep = step
        }
    }

    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        guard let userId = authService.currentUser?.id else { return }
        
        // 重置上传状态
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
            // 更新当前上传项目
            uploadingCount = index + 1
            
            // 判断类型
            let supported = item.supportedContentTypes
            let isVideo = supported.contains(where: { $0.conforms(to: .movie) })
            
            do {
                // 模拟上传进度
                let baseProgress = Double(index) / Double(totalUploadCount)
                let itemProgress = 1.0 / Double(totalUploadCount)
                
                // 上传开始
                await updateUploadProgress(baseProgress + itemProgress * 0.1)
                
                if isVideo {
                    // 上传视频（真实进度）
                    await updateUploadProgress(baseProgress + itemProgress * 0.1)
                    if let data = try await item.loadTransferable(type: Data.self) {
                        // 体积预检
                        if data.count > maxVideoBytes {
                            throw NSError(domain: "Create", code: 413, userInfo: [NSLocalizedDescriptionKey: "视频过大，建议截取更短片段或压缩后再试（≤25MB）"])
                        }

                        let url = try await supabaseService.uploadPostMediaWithProgress(
                            data: data,
                            mime: "video/mp4",
                            fileName: nil,
                            folder: "posts/\(userId)/videos",
                            bucket: "media",
                            isPublic: true,
                            onProgress: { p in
                                Task { await updateUploadProgress(baseProgress + itemProgress * p) }
                            }
                        )

                        newURLs.append(url)
                        await MainActor.run {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                mediaURLs.append(url)
                            }
                        }
                    } else {
                        throw NSError(domain: "Create", code: -21, userInfo: [NSLocalizedDescriptionKey: "无法读取视频数据"])
                    }
                } else {
                    // 上传图片：先压缩到目标体积，再走带进度上传
                    await updateUploadProgress(baseProgress + itemProgress * 0.1)
                    if let rawData = try await item.loadTransferable(type: Data.self), let image = UIImage(data: rawData) {
                        let compressed = try await compressImageDataIfNeeded(image: image, maxBytes: maxImageBytes)

                        let url = try await supabaseService.uploadPostMediaWithProgress(
                            data: compressed,
                            mime: "image/jpeg",
                            fileName: nil,
                            folder: "posts/\(userId)/images",
                            bucket: "media",
                            isPublic: true,
                            onProgress: { p in
                                Task { await updateUploadProgress(baseProgress + itemProgress * p) }
                            }
                        )
                        newURLs.append(url)
                        
                        // 添加到媒体列表
                        await MainActor.run {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                mediaURLs.append(url)
                            }
                        }
                    } else {
                        throw NSError(domain: "Create", code: -22, userInfo: [NSLocalizedDescriptionKey: "无法读取图片数据"])
                    }
                }
                
                // 上传完成
                await updateUploadProgress(baseProgress + itemProgress)
                
            } catch {
                let msg = error.localizedDescription
                if msg.contains("maximum allowed size") || (error as NSError).code == 413 {
                    alertMessage = "上传失败：文件过大。请压缩后再试。建议照片≤4MB、视频≤25MB。"
                } else {
                    alertMessage = "上传失败：\(msg)"
                }
                showAlert = true
            }
        }
        
        // 添加成功反馈
        if !newURLs.isEmpty {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Upload Progress Helper
    
    @MainActor
    private func updateUploadProgress(_ progress: Double) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            uploadProgress = progress
        }
    }

    // MARK: - Image Compression Helpers

    /// 压缩图片至不超过 maxBytes（优先降低质量，其次等比缩放）
    private func compressImageDataIfNeeded(image: UIImage, maxBytes: Int) async throws -> Data {
        // 先尝试质量压缩
        var quality: CGFloat = 0.85
        var data = image.jpegData(compressionQuality: quality)
        if let d = data, d.count <= maxBytes { return d }

        // 逐步降低质量直到 0.4
        while quality > 0.4 {
            quality -= 0.1
            data = image.jpegData(compressionQuality: quality)
            if let d = data, d.count <= maxBytes { return d }
        }

        // 仍超限则按比例缩放（最长边限制到 1280）
        let targetMaxSide: CGFloat = 1280
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale = min(1.0, targetMaxSide / maxSide)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let scaled = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        guard let scaledImage = scaled, let scaledData = scaledImage.jpegData(compressionQuality: 0.7) else {
            throw NSError(domain: "Compression", code: -1, userInfo: [NSLocalizedDescriptionKey: "图片压缩失败"])
        }

        if scaledData.count <= maxBytes { return scaledData }

        // 最后兜底再降到 0.5
        if let finalData = scaledImage.jpegData(compressionQuality: 0.5), finalData.count <= maxBytes {
            return finalData
        }
        // 仍超限则抛错，让上层提示用户换更小图片
        throw NSError(domain: "Compression", code: 413, userInfo: [NSLocalizedDescriptionKey: "图片过大，压缩后仍超过上限（≤4MB）"])
    }
}

// MARK: - 媒体区头部（提取以降低类型推断复杂度）

private struct MediaHeader: View {
    let isUploading: Bool

    var body: some View {
        HStack {
            Text("媒体")
                .font(.headline)
            Spacer()
            if isUploading {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("正在上传…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - 添加媒体瓦片（提取以降低类型推断复杂度）

private struct AddMediaTile: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray3), style: StrokeStyle(lineWidth: 1, dash: [6]))
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.title2)
                Text("添加")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(height: 90)
    }
}

// MARK: - PhotosPicker 瓦片（独立提取）

private struct MediaPickerTile: View {
    @Binding var selection: [PhotosPickerItem]
    var onPicked: ([PhotosPickerItem]) -> Void

    var body: some View {
        PhotosPicker(
            selection: $selection,
            selectionBehavior: .ordered,
            matching: .any(of: [.images, .videos]),
            preferredItemEncoding: .automatic
        ) {
            AddMediaTile()
        }
        .onChange(of: selection) { _, newItems in
            guard !newItems.isEmpty else { return }
            // 限制最大选择数为 9（手动裁剪）
            let limited = Array(newItems.prefix(9))
            if limited.count != newItems.count {
                // 丢弃多余项
                selection = limited
            }
            onPicked(limited)
        }
    }
}

// MARK: - 网格单元（提取以降低类型推断复杂度并避免索引失效）

private struct MediaGridItem: View {
    let url: String
    let onTap: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MediaThumb(urlString: url)
                .frame(height: 90)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { onTap() }

            Button(action: onRemove) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.35))
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
                .frame(width: 24, height: 24)
            }
            .offset(x: -6, y: 6)
        }
    }
}

// MARK: - 缩略图

private struct MediaThumb: View {
    let urlString: String

    private func isVideo(_ url: String) -> Bool {
        return url.isVideoURL // 使用扩展中的统一检测方法
    }

    var body: some View {
        ZStack {
            if isVideo(urlString) {
                // 视频缩略图 + 播放图标
                ZStack {
                    // 使用视频第一帧作为缩略图
                    VideoThumbnailView(urlString: urlString)
                    
                    // 播放图标覆盖层
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.6))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "play.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                // 图片缩略图
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(
                                VStack(spacing: 4) {
                                    Image(systemName: "photo.badge.exclamationmark")
                                        .font(.title3)
                                        .foregroundStyle(.red)
                                    Text("加载失败")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

// MARK: - 视频缩略图视图

private struct VideoThumbnailView: View {
    let urlString: String
    @State private var thumbnail: UIImage?
    @State private var isLoading = true
    @State private var hasError = false
    
    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
            } else if hasError {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "video.badge.exclamationmark")
                                .font(.title3)
                                .foregroundStyle(.orange)
                            Text("视频")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
            } else if isLoading {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .overlay(
                        VStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("加载中...")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    )
            }
        }
        .onAppear {
            generateThumbnail()
        }
    }
    
    private func generateThumbnail() {
        guard let url = URL(string: urlString) else {
            hasError = true
            isLoading = false
            return
        }
        
        Task {
            do {
                let asset = AVAsset(url: url)
                let imageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true
                imageGenerator.maximumSize = CGSize(width: 200, height: 200)
                
                let time = CMTime(seconds: 1, preferredTimescale: 600)
                let cgImage = try await imageGenerator.image(at: time).image
                
                await MainActor.run {
                    thumbnail = UIImage(cgImage: cgImage)
                    isLoading = false
                }
            } catch {
                print("生成视频缩略图失败: \(error)")
                await MainActor.run {
                    hasError = true
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateView(draftPost: nil)
    }
    .onAppear {
        // 预览时显示一些示例数据
        print("🎵 创作页面预览 - 音乐功能已就绪")
        print("✅ 可以选择背景音乐")
        print("✅ 支持音乐预览播放")
        print("✅ 动态背景颜色根据音乐类别变化")
        print("✅ 优化的UI设计和动画效果")
    }
}

// MARK: - Full Screen Media Viewer

struct FullscreenMediaViewer: View {
    let urls: [String]
    @Binding var isPresented: Bool
    let index: Int
    
    @State private var currentIndex: Int
    
    init(urls: [String], isPresented: Binding<Bool>, index: Int) {
        self.urls = urls
        self._isPresented = isPresented
        self.index = index
        _currentIndex = State(initialValue: index)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if urls.isEmpty {
                    VStack {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("无媒体内容")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(urls.enumerated()), id: \.offset) { idx, url in
                            MediaFullScreenView(url: url)
                                .tag(idx)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") {
                        isPresented = false
                    }
                    .foregroundStyle(.white)
                }
                
                ToolbarItem(placement: .principal) {
                    if urls.count > 1 {
                        Text("\(currentIndex + 1) / \(urls.count)")
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MediaFullScreenView: View {
    let url: String
    
    private var isVideo: Bool {
        url.isVideoURL
    }
    
    var body: some View {
        ZStack {
            if isVideo {
                // 视频播放器
                VideoPlayerView(urlString: url)
            } else {
                // 图片查看器
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .clipped()
                    case .failure:
                        VStack {
                            Image(systemName: "photo.badge.exclamationmark")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("加载失败")
                                .foregroundStyle(.secondary)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
    }
}

struct VideoPlayerView: View {
    let urlString: String
    
    var body: some View {
        // 简单的视频播放器占位符
        // 在实际应用中，你可以使用 AVPlayerViewController 或其他视频播放器
        VStack {
            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                case .success(let image):
                    ZStack {
                        image
                            .resizable()
                            .scaledToFit()
                        
                        // 播放按钮覆盖层
                        Button {
                            // 实际播放逻辑
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "play.fill")
                                    .font(.system(size: 30, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                case .failure:
                    VStack {
                        Image(systemName: "video.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("视频加载失败")
                            .foregroundStyle(.secondary)
                    }
                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

