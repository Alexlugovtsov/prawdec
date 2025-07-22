//
//  ContentView.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = VideoQueueViewModel()
    @State private var showingFileImporter = false
    @State private var showingErrorAlert = false
    @State private var errorMessage = ""
    
    @StateObject private var directoryPicker = DirectoryPicker()
    @State private var selectedVideo: VideoItem? = nil
    
    var body: some View {
        HSplitView {
            VStack {
                HStack {
                    Button(action: {
                        showingFileImporter = true
                    }) {
                        HStack {
                            Image(systemName: "plus")
                            Text("Add Video")
                        }
                    }
                    .padding()
                    .buttonStyle(BorderlessButtonStyle())
                    
                    Spacer()
                    
                    Button(action: {
                        if let video = viewModel.videoQueue.first(where: { $0.status == .pending }) {
                            viewModel.startConversion(for: video)
                        }
                    }) {
                        HStack {
                            Image(systemName: "play.circle")
                            Text("Start Conversion")
                        }
                    }
                    .padding()
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(viewModel.videoQueue.isEmpty)
                    //.disabled(selectedVideo == nil || selectedVideo?.status != .pending)
                    
                    Button(action: {
                        viewModel.cancelAllConversions()
                    }) {
                        HStack {
                            Image(systemName: "stop.circle")
                            Text("Cancel Conversion")
                        }
                    }
                    .padding()
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(!viewModel.isAnyConversionInProgress)
                }
                .padding([.top, .horizontal])
                
                List(selection: $selectedVideo) {
                    ForEach(viewModel.videoQueue) { video in
                        VideoRowView(video: video, cancelAction: {
                            viewModel.cancelConversion(for: video)
                        }, removeAction: {
                            if video == selectedVideo {
                                selectedVideo = nil
                            }
                            viewModel.removeVideo(video: video)
                        })
                        .tag(video)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listStyle(SidebarListStyle())
            }
            .frame(minWidth: 700)
            
            if let video = selectedVideo {
                VideoDetailView(video: video, directoryPicker: directoryPicker)
                    .frame(minWidth: 300, maxWidth: 300, maxHeight: .infinity)
            } else {
                Text("Select a video to view and edit its properties")
                    .foregroundColor(.gray)
                    .frame(minWidth: 300, maxWidth: 300, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                viewModel.addVideos(urls: urls)
            case .failure(let error):
                errorMessage = "File import failed: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"),
                  message: Text(errorMessage),
                  dismissButton: .default(Text("OK")))
        }
    }
}

#Preview {
    ContentView()
}
