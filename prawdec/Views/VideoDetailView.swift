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
            Text("Video Properties")
                .font(.title)
                .padding(.top)
            
            HStack {
                Text("File Name")
                    .bold()
                Text(video.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            HStack {
                Text("Output Directory")
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
//                .help("Choose Output Directory")
            }
//            HStack {
//                Toggle("Export Audio", isOn: $video.extractAudio)
//                                .toggleStyle(CheckboxToggleStyle())
//                                .padding()
//            }
            
            Spacer()
        }
        .padding()
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"),
                  message: Text(errorMessage),
                  dismissButton: .default(Text("OK")))
        }
    }
    
    private func chooseOutputDirectory() {
        directoryPicker.pickDirectory { url in
            if let url = url {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    print("Unable to access the security scope of the selected directory")
                    errorMessage = "Unable to access the security scope of the selected directory."
                    showingErrorAlert = true
                    return
                }
                // Update output directory
                DispatchQueue.main.async {
                    video.outputDirectory = url.path
                }
                // Stop accessing security scope
                url.stopAccessingSecurityScopedResource()
                print("Output directory updated: \(video.outputDirectory)")
            }
        }
    }
}
