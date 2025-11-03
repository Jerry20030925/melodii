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

struct CreateView: View {
    // 外部传入：草稿（可选）
    let draftPost: Post?

    // 依赖服务
    @ObservedObject private var authService = AuthService.shared
    @ObservedObject private var supabaseService = SupabaseService.shared
    @ObservedObject private var locationService = LocationService.shared

    // 表单状态
    @State private var text: String = ""
    @State private var mediaURLs: [String] = []         // 已上传成功的媒体URL（图片/视频混合）
    @State private var topics: [String] = []
    @State private var moodTags: [String] = []

    // 选项区状态
    @State private var city: String = ""
    @State private var isLocating: Bool = false
    @State private var isAnonymous: Bool = false

    // 其它 UI 状态
    @State private var isSubmitting: Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""

    // 媒体选择/上传
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading: Bool = false

    // 全屏预览
    @State private var showViewer = false
    @State private var viewerIndex = 0

    // 键盘控制
    @FocusState private var isTextEditorFocused: Bool

    // Extracted grid columns to reduce type-checking complexity
    private static let mediaGridColumns: [GridItem] = [GridItem(.adaptive(minimum: 90), spacing: 8)]

    init(draftPost: Post?) {
        self.draftPost = draftPost
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 文本输入
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            ZStack(alignment: .topLeading) {
                                if text.isEmpty {
                                    Text("说点什么…")
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 16)
                                        .allowsHitTesting(false)
                                }
                            }
                        )
                        .focused($isTextEditorFocused)
                        .scrollContentBackground(.hidden)

                    // 媒体网格 + 选择器
                    mediaSection

                    // 选项区（定位 + 匿名）
                    optionsSection

                    // 话题与标签（占位）
                    tagsSection
                }
                .padding(16)
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
            .task {
                if let draft = draftPost {
                    text = draft.text ?? ""
                    mediaURLs = draft.mediaURLs
                    topics = draft.topics
                    moodTags = draft.moodTags
                    city = draft.city ?? ""
                    isAnonymous = draft.isAnonymous
                }
            }
            .onReceive(locationService.$currentCity.compactMap { $0 }) { newCity in
                city = newCity
                isLocating = false
            }
            .alert("提示", isPresented: $showAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showViewer) {
                FullscreenMediaViewer(urls: mediaURLs, isPresented: $showViewer, index: viewerIndex)
            }
        }
    }

    // MARK: - 媒体区域

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MediaHeader(isUploading: isUploading)

            // 网格预览
            LazyVGrid(columns: Self.mediaGridColumns, spacing: 8) {
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
                            withAnimation(.easeInOut) {
                                if idx < mediaURLs.count && mediaURLs[idx] == url {
                                    mediaURLs.remove(at: idx)
                                } else if let currentIndex = mediaURLs.firstIndex(of: url) {
                                    mediaURLs.remove(at: currentIndex)
                                }
                            }
                        }
                    )
                }

                // 添加按钮（提取为独立视图以减轻类型推断压力）
                MediaPickerTile(
                    selection: $pickerItems,
                    onPicked: { items in
                        Task { await handlePickedItems(items) }
                    }
                )
            }
        }
    }

    // MARK: - 选项区（定位 + 匿名）

    private var optionsSection: some View {
        VStack(spacing: 20) {
            Button {
                requestLocation()
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.15), .mint.opacity(0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 40, height: 40)

                        if isLocating {
                            ProgressView()
                                .tint(.green)
                        } else {
                            Image(systemName: "location.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(city.isEmpty ? "添加位置" : city)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(isLocating ? "正在定位..." : (city.isEmpty ? "点击获取当前位置" : "点击重新定位"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !city.isEmpty && !isLocating {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                city = ""
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(city.isEmpty ? Color(.systemGray6) : Color.green.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(city.isEmpty ? Color.clear : Color.green.opacity(0.2), lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.2), value: city)
                .animation(.easeInOut(duration: 0.2), value: isLocating)
            }
            .disabled(isLocating)
            .buttonStyle(.plain)

            Toggle(isOn: $isAnonymous) {
                HStack(spacing: 12) {
                    Image(systemName: isAnonymous ? "person.fill.questionmark" : "person.fill")
                        .foregroundStyle(isAnonymous ? .purple : .secondary)
                        .frame(width: 24)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("匿名发布")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(isAnonymous ? "已启用匿名模式" : "隐藏你的个人信息")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .tint(.purple)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isAnonymous ? Color.purple.opacity(0.1) : Color(.systemGray6))
            )
            .animation(.easeInOut(duration: 0.2), value: isAnonymous)
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

    private func requestLocation() {
        guard !isLocating else { return }
        isLocating = true
        city = ""
        locationService.requestCity()
        Task {
            try? await Task.sleep(nanoseconds: 8 * NSEC_PER_SEC)
            if isLocating {
                isLocating = false
            }
        }
    }

    private func submit() async {
        guard let userId = authService.currentUser?.id else {
            alertMessage = "请先登录"
            showAlert = true
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            if let draft = draftPost {
                try await supabaseService.updatePostFull(
                    id: draft.id,
                    text: text,
                    topics: topics,
                    moodTags: moodTags,
                    city: city.isEmpty ? nil : city,
                    isAnonymous: isAnonymous,
                    mediaURLs: mediaURLs,
                    status: .published
                )
                alertMessage = "已更新草稿"
                showAlert = true
            } else {
                _ = try await supabaseService.createPost(
                    authorId: userId,
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    mediaURLs: mediaURLs,
                    topics: topics,
                    moodTags: moodTags,
                    city: city.isEmpty ? nil : city,
                    isAnonymous: isAnonymous
                )
                text = ""
                mediaURLs = []
                topics = []
                moodTags = []
                city = ""
                isAnonymous = false
                alertMessage = "发布成功！"
                showAlert = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } catch {
            alertMessage = "提交失败：\(error.localizedDescription)"
            showAlert = true
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private func handlePickedItems(_ items: [PhotosPickerItem]) async {
        guard let userId = authService.currentUser?.id else { return }
        isUploading = true
        defer { isUploading = false; pickerItems = [] }

        for item in items {
            // 判断类型
            let supported = item.supportedContentTypes
            let isVideo = supported.contains(where: { $0.conforms(to: .movie) })
            do {
                if isVideo {
                    // 尝试拿到文件数据
                    if let data = try await item.loadTransferable(type: Data.self) {
                        let url = try await supabaseService.uploadPostMedia(
                            data: data,
                            mime: "video/mp4",
                            fileName: nil,
                            folder: "posts/\(userId)/videos"
                        )
                        mediaURLs.append(url)
                    } else {
                        throw NSError(domain: "Create", code: -21, userInfo: [NSLocalizedDescriptionKey: "无法读取视频数据"])
                    }
                } else {
                    // 图片压缩为JPEG
                    if let data = try await item.loadTransferable(type: Data.self) {
                        let url = try await supabaseService.uploadPostMedia(
                            data: data,
                            mime: "image/jpeg",
                            fileName: nil,
                            folder: "posts/\(userId)/images"
                        )
                        mediaURLs.append(url)
                    } else {
                        throw NSError(domain: "Create", code: -22, userInfo: [NSLocalizedDescriptionKey: "无法读取图片数据"])
                    }
                }
            } catch {
                alertMessage = "上传失败：\(error.localizedDescription)"
                showAlert = true
            }
        }
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
        let lower = url.lowercased()
        return lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v")
    }

    var body: some View {
        ZStack {
            if isVideo(urlString) {
                // 视频缩略 + 播放图标
                ZStack {
                    AsyncImage(url: URL(string: urlString)) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .overlay(ProgressView())
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .overlay(Image(systemName: "video.slash").foregroundStyle(.secondary))
                        @unknown default:
                            EmptyView()
                        }
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                AsyncImage(url: URL(string: urlString)) { phase in
                    switch phase {
                    case .empty:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(ProgressView())
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.systemGray6))
                            .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    @unknown default:
                        EmptyView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

#Preview {
    NavigationStack {
        CreateView(draftPost: nil)
    }
}
