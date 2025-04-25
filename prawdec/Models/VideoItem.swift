//
//  VideoItem.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import Foundation
import Combine

enum ConversionStatus: String {
    case pending = "待处理"
    case converting = "转换中"
    case completed = "完成"
    case failed = "失败"
    case cancelled = "已取消"
}

class VideoItem: ObservableObject, Identifiable, Hashable {
    let id: UUID
    let url: URL
    @Published var status: ConversionStatus = .pending
    @Published var progress: Double = 0.0
    @Published var outputDirectory: String
    //@Published var extractAudio: Bool = true

    init(id: UUID = UUID(), url: URL, outputDirectory: String = NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true).first ?? "") {
        self.id = id
        self.url = url
        self.outputDirectory = outputDirectory
    }
    
    // MARK: - Hashable Conformance
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Equatable Conformance
    
    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        return lhs.id == rhs.id
    }
}
