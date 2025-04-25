//
//  VideoRowView.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import SwiftUI

struct VideoRowView: View {
    @ObservedObject var video: VideoItem
    var cancelAction: () -> Void
    var removeAction: () -> Void
    
    var body: some View {
        HStack {
            HStack {
                Image(systemName: "film")
                    .foregroundColor(.blue)
                Text(video.url.lastPathComponent)
                    .frame(width: 250, alignment: .leading)
            }
            
            Spacer()
            
            Text(video.status.rawValue)
                .frame(width: 100, alignment: .center)
                .foregroundColor(statusColor)
            
            ProgressView(value: video.progress)
                .frame(width: 200)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
            
            Spacer()
            
            if video.status == .converting {
                Button(action: {
                    cancelAction()
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("取消转换")
            } else {
                Button(action: {
                    removeAction()
                }) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("删除任务")
            }
        }
        .padding(5)
    }
    
    private var statusColor: Color {
        switch video.status {
        case .completed:
            return .green
        case .failed, .cancelled:
            return .red
        case .converting:
            return .orange
        case .pending:
            return .gray
        }
    }
}
