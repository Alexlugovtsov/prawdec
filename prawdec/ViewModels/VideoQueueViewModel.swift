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
    
    // 存储取消任务
    private var conversionTasks: [UUID: () -> Void] = [:]
    
    // 存储每个 VideoItem 的订阅
    private var videoSubscriptions: [UUID: AnyCancellable] = [:]
    
    init() {
        // 观察 videoQueue 的变化
        $videoQueue
            .sink { [weak self] newQueue in
                self?.handleVideoQueueChange(newQueue)
            }
            .store(in: &cancellables)
    }
    
    private func handleVideoQueueChange(_ newQueue: [VideoItem]) {
        // 获取现有的 video IDs 和新队列中的 video IDs
        let existingIds = videoSubscriptions.keys
        let newIds = newQueue.map { $0.id }
        
        // 找出被移除的视频 ID
        let removedIds = existingIds.filter { !newIds.contains($0) }
        for id in removedIds {
            // 取消订阅并移除
            videoSubscriptions[id]?.cancel()
            videoSubscriptions.removeValue(forKey: id)
        }
        
        // 为新添加的视频设置订阅
        for video in newQueue {
            if videoSubscriptions[video.id] == nil {
                let subscription = video.$status
                    .sink { [weak self] _ in
                        self?.updateConversionStatus()
                    }
                videoSubscriptions[video.id] = subscription
            }
        }
        
        // 更新转换状态
        updateConversionStatus()
    }
    
    private func updateConversionStatus() {
        // 检查是否有任何视频处于转换中状态
        DispatchQueue.main.async {
            self.isAnyConversionInProgress = self.videoQueue.contains { $0.status == .converting }
        }
    }
    
    func addVideos(urls: [URL]) {
        let newVideos = urls.map { VideoItem(url: $0) }
        DispatchQueue.main.async { // 确保在主线程上更新
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
        //let frameCount = 0 // 0 表示转换所有帧
        
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
                        print("转换失败: \(error.localizedDescription)")
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
            print("转换已取消: \(video.url.lastPathComponent)")
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
                print("转换已取消: \(video.url.lastPathComponent)")
            }
        }
        conversionTasks.removeAll()
    }
}
