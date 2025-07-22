//
//  VideoQueueViewModel.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import Foundation
import Combine

class VideoQueueViewModel: ObservableObject {
    @Published var videoQueue: [VideoItem] = []
    @Published var isAnyConversionInProgress: Bool = false

    private var cancellables = Set<AnyCancellable>()
    private let converter = PRAWConverter()

    // Store cancel tasks
    private var conversionTasks: [UUID: () -> Void] = [:]

    // Store subscriptions for each VideoItem
    private var videoSubscriptions: [UUID: AnyCancellable] = [:]

    init() {
        // Observe changes to videoQueue
        $videoQueue
            .sink { [weak self] newQueue in
                self?.handleVideoQueueChange(newQueue)
            }
            .store(in: &cancellables)
    }

    private func handleVideoQueueChange(_ newQueue: [VideoItem]) {
        // Get existing video IDs and new queue video IDs
        let existingIds = videoSubscriptions.keys
        let newIds = newQueue.map { $0.id }

        // Find removed video IDs
        let removedIds = existingIds.filter { !newIds.contains($0) }
        for id in removedIds {
            // Cancel subscription and remove
            videoSubscriptions[id]?.cancel()
            videoSubscriptions.removeValue(forKey: id)
        }

        // Set up subscriptions for newly added videos
        for video in newQueue {
            if videoSubscriptions[video.id] == nil {
                let subscription = video.$status
                    .sink { [weak self] _ in
                        self?.updateConversionStatus()
                    }
                videoSubscriptions[video.id] = subscription
            }
        }

        // Update conversion status
        updateConversionStatus()
    }

    private func updateConversionStatus() {
        // Check if any video is in converting status
        DispatchQueue.main.async {
            self.isAnyConversionInProgress = self.videoQueue.contains { $0.status == .converting }
        }
    }

    func addVideos(urls: [URL]) {
        let newVideos = urls.map { VideoItem(url: $0) }
        DispatchQueue.main.async { // Ensure update on main thread
            self.videoQueue.append(contentsOf: newVideos)
        }
    }

    func removeVideo(video: VideoItem) {
        DispatchQueue.main.async {
            self.videoQueue.removeAll(where: { $0.id == video.id })
        }
    }

    func startConversion(for video: VideoItem) {
        guard video.status == .pending else { return }
        convert(video: video)
    }

    private func convert(video: VideoItem) {
        DispatchQueue.main.async {
            video.status = .converting
            video.progress = 0.0
        }

        let inputPath = video.url.path
        let outputDirectory = video.outputDirectory
        // let frameCount = 0 // 0 means convert all frames

        converter.convertProResRawToDNG(withInputPath: inputPath, outputDirectory: outputDirectory, /* frameCount: frameCount ,*/ progressBlock: { [weak video] progress in
            DispatchQueue.main.async {
                video?.progress = progress
            }
        }, completionBlock: { [weak self, weak video] success, error in
            guard let self = self, let video = video else { return }
            DispatchQueue.main.async {
                if success {
                    video.status = .completed
                } else if (error?.localizedDescription == "Conversion was cancelled by the user.") {
                    video.status = .cancelled
                } else {
                    video.status = .failed
                    if let error = error {
                        print("Conversion failed: \(error.localizedDescription)")
                    }
                }
                self.conversionTasks.removeValue(forKey: video.id)
            }
        })

        conversionTasks[video.id] = { [weak self] in
            self?.converter.cancelConversion()
            DispatchQueue.main.async {
                video.status = .cancelled
            }
            print("Conversion cancelled: \(video.url.lastPathComponent)")
        }
    }

    func cancelConversion(for video: VideoItem) {
        if let cancelTask = conversionTasks[video.id] {
            cancelTask()
            conversionTasks.removeValue(forKey: video.id)
        }
    }

    func cancelAllConversions() {
        for (id, cancelTask) in conversionTasks {
            cancelTask()
            if let video = videoQueue.first(where: { $0.id == id }) {
                DispatchQueue.main.async {
                    video.status = .cancelled
                }
                print("Conversion cancelled: \(video.url.lastPathComponent)")
            }
        }
        conversionTasks.removeAll()
    }
}
