//
//  MoodSelectionSection.swift
//  Melodii
//
//  心情选择组件
//

import SwiftUI

struct MoodSelectionSection: View {
    @Binding var selectedMood: CreativeMood
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("创作心情")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("影响颜色主题和建议")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 心情网格
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(CreativeMood.allCases, id: \.self) { mood in
                    CreativeMoodCard(
                        mood: mood,
                        isSelected: selectedMood == mood
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            selectedMood = mood
                        }
                    }
                }
            }
            
            // 当前心情效果预览
            VStack(spacing: 8) {
                Text("主题预览")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                HStack(spacing: 4) {
                    // 主色调
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedMood.primaryColor)
                        .frame(height: 20)
                    
                    // 辅助色调
                    RoundedRectangle(cornerRadius: 4)
                        .fill(selectedMood.secondaryColor)
                        .frame(height: 20)
                    
                    // 渐变预览
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [selectedMood.primaryColor, selectedMood.secondaryColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 20)
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

struct CreativeMoodCard: View {
    let mood: CreativeMood
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Text(mood.emoji)
                    .font(.system(size: 32))
                    .scaleEffect(isSelected ? 1.2 : 1.0)
                
                Text(mood.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    if isSelected {
                        LinearGradient(
                            colors: [mood.primaryColor, mood.secondaryColor],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    } else {
                        Color(.systemGray6)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        isSelected ? mood.primaryColor.opacity(0.6) : Color(.systemGray4),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .scaleEffect(isSelected ? 1.05 : 1.0)
            .shadow(
                color: isSelected ? mood.primaryColor.opacity(0.3) : .clear,
                radius: isSelected ? 8 : 0,
                x: 0,
                y: isSelected ? 4 : 0
            )
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }
}

#Preview {
    MoodSelectionSection(selectedMood: .constant(.casual))
}
