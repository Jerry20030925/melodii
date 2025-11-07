// 整个文件替换为以下版本

import SwiftUI
import PhotosUI

struct EnhancedEmojiStickerPicker: View {
    let onEmojiSelect: (String) -> Void
    let onStickerSelect: (String) -> Void // 传递图片URL

    @ObservedObject private var stickerManager = CustomStickerManager.shared
    @State private var selectedTab = 0
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDeleteConfirmation = false
    @State private var stickerToDelete: CustomSticker?
    @State private var isUploading = false

    // 更多表情类别（保持不变，略）
    private let emojiCategories: [EmojiCategory] = [
        // ... 原有类别数组保持不变 ...
        EmojiCategory(
            name: "笑脸",
            icon: "😊",
            emojis: [
                "😀","😃","😄","😁","😆","😅","🤣","😂","🙂","🙃",
                "😉","😊","😇","🥰","😍","🤩","😘","😗","☺️","😚",
                "😙","🥲","😋","😛","😜","🤪","😝","🤑","🤗","🤭",
                "🤫","🤔","🤐","🤨","😐","😑","😶","😏","😒","🙄",
                "😬","🤥","😌","😔","😪","🤤","😴","😷","🤒","🤕"
            ]
        ),
        EmojiCategory(name: "手势", icon: "👋", emojis: ["👋","🤚","🖐","✋","🖖","👌","🤌","🤏","✌️","🤞","🤟","🤘","🤙","👈","👉","👆","🖕","👇","☝️","👍","👎","✊","👊","🤛","🤜","👏","🙌","👐","🤲","🤝","🙏","✍️","💅","🤳","💪","🦾","🦿","🦵","🦶","👂"]),
        EmojiCategory(name: "爱心", icon: "❤️", emojis: ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💟","☮️","✝️","☪️","🕉","☸️","✡️","🔯","🕎","☯️","☦️","🛐"]),
        EmojiCategory(name: "动物", icon: "🐶", emojis: ["🐶","🐱","🐭","🐹","🐰","🦊","🐻","🐼","🐨","🐯","🦁","🐮","🐷","🐸","🐵","🐔","🐧","🐦","🐤","🐣","🦆","🦅","🦉","🦇","🐺","🐗","🐴","🦄","🐝","🐛","🦋","🐌","🐞","🐜","🦟","🦗","🕷","🦂","🐢","🐍"]),
        EmojiCategory(name: "食物", icon: "🍕", emojis: ["🍎","🍊","🍋","🍌","🍉","🍇","🍓","🫐","🍈","🍒","🍑","🥭","🍍","🥥","🥝","🍅","🍆","🥑","🥦","🥬","🥒","🌶","🫑","🌽","🥕","🫒","🧄","🧅","🥔","🍠","🍞","🥐","🥖","🫓","🥨","🥯","🧇","🥞","🧈","🍕","🍔","🍟","🌭","🥪","🌮","🌯","🫔","🥙","🧆","🍳"]),
        EmojiCategory(name: "活动", icon: "⚽", emojis: ["⚽","🏀","🏈","⚾","🥎","🎾","🏐","🏉","🥏","🎱","🪀","🏓","🏸","🏒","🏑","🥍","🏏","🥅","⛳","🪁","🏹","🎣","🤿","🥊","🥋","🎽","🛹","🛼","🛷","⛸","🥌","🎿","⛷","🏂","🪂","🏋️","🤼","🤸","🤺","⛹️"]),
        EmojiCategory(name: "旅行", icon: "✈️", emojis: ["🚗","🚕","🚙","🚌","🚎","🏎","🚓","🚑","🚒","🚐","🛻","🚚","🚛","🚜","🦯","🦽","🦼","🛴","🚲","🛵","🏍","🛺","🚨","🚔","🚍","🚘","🚖","🚡","🚠","🚟","🚃","🚋","🚞","🚝","🚄","🚅","🚈","🚂","🚆","✈️","🛫","🛬","🪂","💺","🚁","🛩","🛰","🚀","🛸","🚢"]),
        EmojiCategory(name: "物品", icon: "⌚", emojis: ["⌚","📱","📲","💻","⌨️","🖥","🖨","🖱","🖲","🕹","🗜","💽","💾","💿","📀","📼","📷","📸","📹","🎥","📽","🎞","📞","☎️","📟","📠","📺","📻","🎙","🎚","🎛","🧭","⏱","⏲","⏰","🕰","⌛","⏳","📡","🔋"]),
        EmojiCategory(name: "符号", icon: "⭐", emojis: ["❤️","🧡","💛","💚","💙","💜","🖤","🤍","🤎","💔","❣️","💕","💞","💓","💗","💖","💘","💝","💟","☮️","✨","💫","⭐","🌟","✅","❌","⚠️","🔥","💯","👏","🎉","🎊","🎈","🎁","🏆","🥇","🥈","🥉","⚡","💥"])
    ]

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            TabView(selection: $selectedTab) {
                emojiPickerView.tag(0)
                customStickerView.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .frame(height: 320)
        .background(Color(.systemGray6))
        .onChange(of: selectedPhotoItem) { _, newValue in
            if newValue != nil {
                Task { await handleImageSelection() }
            }
        }
        .alert("删除表情包", isPresented: $showDeleteConfirmation) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                if let sticker = stickerToDelete {
                    Task { await deleteSticker(sticker) }
                }
            }
        } message: { Text("确定要删除这个表情包吗？") }
    }

    private var tabBar: some View {
        HStack(spacing: 20) {
            Button {
                withAnimation(.spring(response: 0.3)) { selectedTab = 0 }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "face.smiling").font(.title3)
                    Text("表情").font(.caption)
                }
                .foregroundStyle(selectedTab == 0 ? .blue : .secondary)
                .frame(maxWidth: .infinity)
            }
            Button {
                withAnimation(.spring(response: 0.3)) { selectedTab = 1 }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled").font(.title3)
                    Text("表情包").font(.caption)
                }
                .foregroundStyle(selectedTab == 1 ? .blue : .secondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    @State private var selectedCategory = 0
    private var emojiPickerView: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(emojiCategories.enumerated()), id: \.offset) { index, category in
                        Button {
                            withAnimation(.spring(response: 0.3)) { selectedCategory = index }
                        } label: {
                            VStack(spacing: 4) {
                                Text(category.icon).font(.title3)
                                Text(category.name).font(.caption2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedCategory == index ? Color.blue.opacity(0.15) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 12) {
                    ForEach(emojiCategories[selectedCategory].emojis, id: \.self) { emoji in
                        Button {
                            onEmojiSelect(emoji)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            
                            // 添加选择动画效果
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                // 可以在这里添加一些临时状态变化
                            }
                        } label: {
                            Text(emoji)
                                .font(.system(size: 32))
                                .scaleEffect(1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: emoji)
                        }
                        .buttonStyle(AnimatedEmojiButtonStyle())
                    }
                }
                .padding()
            }
        }
    }

    private var customStickerView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("我的表情包").font(.headline).foregroundStyle(.primary)
                Spacer()
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加")
                    }
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    .clipShape(Capsule())
                }
                .disabled(isUploading)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            if stickerManager.isLoading {
                VStack { ProgressView(); Text("加载中...").font(.caption).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if stickerManager.customStickers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 50)).foregroundStyle(.secondary)
                    Text("还没有自定义表情包").font(.subheadline).foregroundStyle(.secondary)
                    Text("点击右上角添加按钮上传图片").font(.caption).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(stickerManager.customStickers) { sticker in
                            StickerCell(
                                sticker: sticker,
                                onTap: {
                                    onStickerSelect(sticker.imageURL) // 这里保证是远端URL
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                },
                                onDelete: {
                                    stickerToDelete = sticker
                                    showDeleteConfirmation = true
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
        }
    }

    // 上传选中的图片为贴纸：保留原格式，上传后写入自定义表情表，再刷新列表
    private func handleImageSelection() async {
        guard let item = selectedPhotoItem else { return }
        isUploading = true
        defer { isUploading = false; selectedPhotoItem = nil }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "Sticker", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法读取图片数据"])
            }
            // 直接通过 SupabaseService 上传，确保拿到可访问 URL
            guard let uid = AuthService.shared.currentUser?.id else { throw NSError(domain: "Sticker", code: -2, userInfo: [NSLocalizedDescriptionKey: "未登录"]) }
            let remoteURL = try await SupabaseService.shared.uploadStickerImage(data: data, userId: uid, isPublic: true)

            // 写入自定义表情记录
            _ = try await SupabaseService.shared.createCustomSticker(userId: uid, imageURL: remoteURL, name: nil)

            // 让 Manager 刷新（如果它内部有缓存）
            await MainActor.run {
                CustomStickerManager.shared.loadStickers()
            }

            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            print("❌ 上传表情包失败: \(error)")
        }
    }

    private func deleteSticker(_ sticker: CustomSticker) async {
        do {
            try await stickerManager.deleteSticker(sticker)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            print("❌ 删除表情包失败: \(error)")
        }
    }
}

// 其余辅助视图与样式保持不变
private struct StickerCell: View {
    let sticker: CustomSticker
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button { onTap() } label: {
            AsyncImage(url: URL(string: sticker.imageURL)) { phase in
                switch phase {
                case .empty:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5))
                        ProgressView()
                    }
                    .aspectRatio(1, contentMode: .fit)
                case .success(let image):
                    image
                        .resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(.systemGray4), lineWidth: 1))
                case .failure:
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray5))
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                    }
                    .aspectRatio(1, contentMode: .fit)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: { Label("删除", systemImage: "trash") }
        }
        .scaleEffect(isPressed ? 0.9 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
    }
}

private struct EmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.2 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// 增强版表情按钮样式，带有更丰富的动画效果
private struct AnimatedEmojiButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.2 : 1.0)
            .brightness(configuration.isPressed ? 0.1 : 0.0)
            .shadow(color: .blue.opacity(configuration.isPressed ? 0.3 : 0), radius: configuration.isPressed ? 4 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct EmojiCategory { let name: String; let icon: String; let emojis: [String] }
