//
//  VideoItem.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import Foundation
import Combine

enum ConversionStatus: String {
    case pending = "Pending"
    case converting = "Converting"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

class VideoItem: ObservableObject, Identifiable, Hashable {
    let id: UUID
    let url: URL
    @Published var status: ConversionStatus = .pending
    @Published var progress: Double = 0.0
    @Published var outputDirectory: String
    //@Published var extractAudio: Bool = true

    init(id: UUID = UUID(), url: URL, outputDirectory: String? = nil) {
        self.id = id
        self.url = url

        if let customOutput = outputDirectory {
            self.outputDirectory = customOutput
        } else {
            // File name without extension
            let fileName = url.deletingPathExtension().lastPathComponent

            // Directory containing the original file
            let baseDirectory = url.deletingLastPathComponent()

            // Path to the subdirectory
            let outputURL = baseDirectory.appendingPathComponent(fileName)

            // Create the directory if it doesn't exist
            do {
                try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create output directory: \(error)")
            }

            self.outputDirectory = outputURL.path
        }
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