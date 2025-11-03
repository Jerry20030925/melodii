import SwiftUI
import PhotosUI

struct FullscreenImageViewer: View {
    let urls: [String]
    @Binding var isPresented: Bool
    @State var index: Int

    @State private var controlsHidden = false
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragging = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $index) {
                ForEach(urls.indices, id: \.self) { i in
                    ZoomableAsyncImage(urlString: urls[i])
                        .tag(i)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                controlsHidden.toggle()
                            }
                        }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .updating($isDragging, body: { _, state, _ in
                        state = true
                    })
                    .onChanged { value in
                        // 仅纵向拖拽用于关闭
                        dragOffset = CGSize(width: 0, height: value.translation.height)
                    }
                    .onEnded { value in
                        if abs(value.translation.height) > 120 {
                            isPresented = false
                        } else {
                            withAnimation(.spring) {
                                dragOffset = .zero
                            }
                        }
                    }
            )

            // 顶部栏
            if !controlsHidden {
                topBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 底部栏
            if !controlsHidden {
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .statusBarHidden(true)
        .onDisappear {
            controlsHidden = false
            dragOffset = .zero
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Spacer()
            Text("\(index + 1)/\(urls.count)")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button {
                UIPasteboard.general.string = urls[index]
            } label: {
                Label("复制链接", systemImage: "link")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Button {
                saveCurrentImageToPhotos()
            } label: {
                Label("保存", systemImage: "square.and.arrow.down")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func saveCurrentImageToPhotos() {
        guard let url = URL(string: urls[index]) else { return }
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            } catch {
                print("保存图片失败: \(error)")
            }
        }
    }
}

// 可缩放的异步图片
private struct ZoomableAsyncImage: View {
    let urlString: String

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var doubleTapScale: CGFloat = 1.0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size

            AsyncImage(url: URL(string: urlString)) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .tint(.white)
                        .frame(width: size.width, height: size.height)
                        .background(Color.black)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .background(Color.black)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnificationGesture())
                        .gesture(dragGesture())
                        .onTapGesture(count: 2, perform: {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                if scale > 1.01 {
                                    scale = 1.0
                                    offset = .zero
                                } else {
                                    scale = 2.0
                                }
                            }
                        })
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.white.opacity(0.7))
                        .font(.system(size: 40))
                        .frame(width: size.width, height: size.height)
                        .background(Color.black)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .ignoresSafeArea()
    }

    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                scale = clamp(scale * delta, min: 1.0, max: 4.0)
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1.0
                // 缩小时复位偏移
                if scale <= 1.01 {
                    withAnimation(.spring) {
                        offset = .zero
                        scale = 1.0
                    }
                }
            }
    }

    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in
                // 仅在放大后允许平移
                guard scale > 1.01 else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
