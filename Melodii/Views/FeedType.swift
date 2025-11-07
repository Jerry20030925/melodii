//
//  FeedType.swift
//  Melodii
//
//  Simple feed selector used by HomeView
//

import Foundation

enum FeedType: String, CaseIterable, Codable, Hashable {
    case recommended
    case following
}
