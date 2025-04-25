//
//  VideoDetailView.swift
//  prawdec
//
//  Created by Henri on 2024/11/27.
//

import SwiftUI

struct VideoDetailView: View {
    @ObservedObject var video: VideoItem
    @ObservedObject var directoryPicker: DirectoryPicker
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("视频属性")
                .font(.title)
                .padding(.top)
            
            HStack {
                Text("文件名")
                    .bold()
                Text(video.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            HStack {
                Text("输出目录")
                    .bold()
                Button(action: {
                    chooseOutputDirectory()
                }) {
                    Text(video.outputDirectory)
                        .truncationMode(.head)
                        .lineLimit(1)
                }
//                Text(video.outputDirectory)
//                    .lineLimit(1)
//                    .truncationMode(.middle)
//                Button(action: {
//                    chooseOutputDirectory()
//                }) {
//                    Image(systemName: "folder")
//                }
//                .buttonStyle(BorderlessButtonStyle())
//                .help("选择输出目录")
            }
//            HStack {
//                Toggle("导出音频", isOn: $video.extractAudio)
//                                .toggleStyle(CheckboxToggleStyle())
//                                .padding()
//            }
            
            Spacer()
        }
        .padding()
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("错误"),
                  message: Text(errorMessage),
                  dismissButton: .default(Text("确定")))
        }
    }
    
    private func chooseOutputDirectory() {
        directoryPicker.pickDirectory { url in
            if let url = url {
                // 开始访问安全范围
                guard url.startAccessingSecurityScopedResource() else {
                    print("无法访问所选目录的安全范围")
                    errorMessage = "无法访问所选目录的安全范围。"
                    showingErrorAlert = true
                    return
                }
                // 更新输出目录
                DispatchQueue.main.async {
                    video.outputDirectory = url.path
                }
                // 停止访问安全范围
                url.stopAccessingSecurityScopedResource()
                print("输出目录已更新: \(video.outputDirectory)")
            }
        }
    }
}
