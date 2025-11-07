//
//  TemplateSelectionSection.swift
//  Melodii
//
//  专业模板选择组件
//

import SwiftUI

struct TemplateSelectionSection: View {
    @Binding var selectedTemplate: CreativeTemplate?
    @Binding var showTemplateSelector: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("创作模板")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("浏览全部") {
                    showTemplateSelector = true
                }
                .font(.caption)
                .foregroundStyle(.blue)
            }
            
            if let template = selectedTemplate {
                // 当前选择的模板
                VStack(spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(template.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Text(template.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        Button("更换") {
                            showTemplateSelector = true
                        }
                        .font(.caption)
                        .foregroundStyle(.blue)
                        
                        Button("移除") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                selectedTemplate = nil
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                    
                    // 模板预览
                    Text(template.placeholder)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    
                    // 建议标签
                    if !template.suggestedTags.isEmpty {
                        HStack {
                            Text("建议标签:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            ForEach(template.suggestedTags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(template.mood.primaryColor.opacity(0.3), lineWidth: 2)
                )
                .shadow(color: template.mood.primaryColor.opacity(0.1), radius: 4, x: 0, y: 2)
            } else {
                // 推荐模板网格
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(CreativeTemplate.presets.prefix(4)) { template in
                        TemplateCard(template: template) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                selectedTemplate = template
                            }
                        }
                    }
                }
                
                Button("查看更多模板") {
                    showTemplateSelector = true
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), style: StrokeStyle(lineWidth: 1, dash: [5]))
                )
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

struct TemplateCard: View {
    let template: CreativeTemplate
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.mood.emoji)
                        .font(.title2)
                    
                    Spacer()
                    
                    Circle()
                        .fill(template.mood.primaryColor)
                        .frame(width: 8, height: 8)
                }
                
                Text(template.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                
                Text(template.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer(minLength: 8)
            }
            .padding(12)
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [
                        template.mood.primaryColor.opacity(0.1),
                        template.mood.secondaryColor.opacity(0.05)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(template.mood.primaryColor.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TemplateSelectorSheet: View {
    @Binding var selectedTemplate: CreativeTemplate?
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedCategory = "全部"
    
    private let categories = ["全部", "生活", "旅行", "美食", "艺术", "工作"]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 分类选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(categories, id: \.self) { category in
                            Button(category) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedCategory = category
                                }
                            }
                            .foregroundStyle(selectedCategory == category ? .white : .primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(selectedCategory == category ? Color.blue : Color(.systemGray6))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.vertical, 16)
                
                // 模板网格
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(filteredTemplates) { template in
                            TemplateDetailCard(template: template, isSelected: selectedTemplate?.id == template.id) {
                                selectedTemplate = template
                                dismiss()
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("选择模板")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private var filteredTemplates: [CreativeTemplate] {
        if selectedCategory == "全部" {
            return CreativeTemplate.presets
        } else {
            return CreativeTemplate.presets.filter { $0.category == selectedCategory }
        }
    }
}

struct TemplateDetailCard: View {
    let template: CreativeTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text(template.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(template.mood.emoji)
                        .font(.title2)
                }
                
                Text(template.placeholder)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                HStack {
                    ForEach(template.suggestedTags.prefix(2), id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(template.mood.primaryColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(template.mood.primaryColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? Color.green : template.mood.primaryColor.opacity(0.2),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .shadow(color: isSelected ? Color.green.opacity(0.2) : .clear, radius: 8, x: 0, y: 4)
            .scaleEffect(isSelected ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    TemplateSelectionSection(
        selectedTemplate: .constant(nil),
        showTemplateSelector: .constant(false)
    )
}