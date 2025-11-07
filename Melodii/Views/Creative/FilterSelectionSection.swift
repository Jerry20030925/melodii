//
//  FilterSelectionSection.swift
//  Melodii
//
//  滤镜选择组件
//

import SwiftUI

struct FilterSelectionSection: View {
    @Binding var appliedFilters: [ImageFilter]
    @Binding var showFilterSelector: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("图片滤镜")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if !appliedFilters.isEmpty {
                    Button("清除全部") {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            appliedFilters = []
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
                
                Button("自定义") {
                    showFilterSelector = true
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            
            if !appliedFilters.isEmpty {
                // 已应用的滤镜
                VStack(alignment: .leading, spacing: 12) {
                    Text("已应用滤镜")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 8)
                    ], spacing: 8) {
                        ForEach(Array(appliedFilters.enumerated()), id: \.offset) { index, filter in
                            AppliedFilterCard(filter: filter) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    _ = appliedFilters.remove(at: index)
                                }
                            }
                        }
                    }
                    
                    // 滤镜效果预览
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(.systemGray6),
                                    Color(.systemGray5)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            // 滤镜效果叠加
                            ZStack {
                                ForEach(appliedFilters.indices, id: \.self) { index in
                                    Rectangle()
                                        .fill(appliedFilters[index].color.opacity(appliedFilters[index].intensity))
                                        .blendMode(.overlay)
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        )
                        .overlay(
                            Text("滤镜预览效果")
                                .font(.caption)
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule()),
                            alignment: .center
                        )
                }
            } else {
                // 预设滤镜选择
                VStack(alignment: .leading, spacing: 12) {
                    Text("快速滤镜")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 80), spacing: 8)
                    ], spacing: 8) {
                        ForEach(ImageFilter.presets) { filter in
                            QuickFilterCard(filter: filter) {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                    appliedFilters.append(filter)
                                }
                            }
                        }
                    }
                    
                    Button("高级滤镜编辑") {
                        showFilterSelector = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
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

struct AppliedFilterCard: View {
    let filter: ImageFilter
    let onRemove: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(filter.color)
                .frame(width: 16, height: 16)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text("\(Int(filter.intensity * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(filter.color.opacity(0.3), lineWidth: 1)
        )
    }
}

struct QuickFilterCard: View {
    let filter: ImageFilter
    let onApply: () -> Void
    
    var body: some View {
        Button(action: onApply) {
            VStack(spacing: 6) {
                // 滤镜颜色预览
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray6),
                                filter.color.opacity(filter.intensity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 40)
                    .overlay(
                        Text(filter.name.prefix(1).uppercased())
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle()),
                        alignment: .topTrailing
                    )
                
                Text(filter.name)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct FilterEditorSheet: View {
    @Binding var appliedFilters: [ImageFilter]
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedFilter: ImageFilter?
    @State private var customIntensity: Double = 0.5
    @State private var customColor: Color = .blue
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 预设滤镜
                VStack(alignment: .leading, spacing: 16) {
                    Text("预设滤镜")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 100), spacing: 12)
                    ], spacing: 12) {
                        ForEach(ImageFilter.presets) { filter in
                            FilterPreviewCard(
                                filter: filter,
                                isApplied: appliedFilters.contains { $0.name == filter.name }
                            ) {
                                toggleFilter(filter)
                            }
                        }
                    }
                }
                
                Divider()
                
                // 自定义滤镜
                VStack(alignment: .leading, spacing: 16) {
                    Text("自定义滤镜")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    VStack(spacing: 12) {
                        HStack {
                            Text("颜色")
                                .font(.subheadline)
                            
                            Spacer()
                            
                            ColorPicker("选择颜色", selection: $customColor)
                                .labelsHidden()
                        }
                        
                        HStack {
                            Text("强度")
                                .font(.subheadline)
                            
                            Slider(value: $customIntensity, in: 0...1)
                                .tint(customColor)
                            
                            Text("\(Int(customIntensity * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        
                        Button("添加自定义滤镜") {
                            let customFilter = ImageFilter(
                                name: "自定义",
                                intensity: customIntensity,
                                color: customColor
                            )
                            appliedFilters.append(customFilter)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(customColor.opacity(0.1))
                        .foregroundStyle(customColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                
                Spacer()
            }
            .padding(20)
            .navigationTitle("滤镜编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func toggleFilter(_ filter: ImageFilter) {
        if let index = appliedFilters.firstIndex(where: { $0.name == filter.name }) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                _ = appliedFilters.remove(at: index)
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appliedFilters.append(filter)
            }
        }
    }
}

struct FilterPreviewCard: View {
    let filter: ImageFilter
    let isApplied: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 8) {
                // 滤镜效果预览
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(.systemGray6),
                                Color(.systemGray5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 60)
                    .overlay(
                        Rectangle()
                            .fill(filter.color.opacity(filter.intensity))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .blendMode(.overlay)
                    )
                    .overlay(
                        isApplied ?
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .background(Color.white)
                            .clipShape(Circle())
                            .padding(4)
                        : nil,
                        alignment: .topTrailing
                    )
                
                VStack(spacing: 2) {
                    Text(filter.name)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    Text("\(Int(filter.intensity * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isApplied ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isApplied)
    }
}

#Preview {
    FilterSelectionSection(
        appliedFilters: .constant([]),
        showFilterSelector: .constant(false)
    )
}