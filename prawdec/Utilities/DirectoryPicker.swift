//
//  DirectoryPicker.swift
//  prawdec
//
//  Created by Henri on 2024/11/25.
//

import Foundation
import AppKit

class DirectoryPicker: ObservableObject {
    func pickDirectory(completion: @escaping (URL?) -> Void) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.title = "选择输出目录"
            panel.prompt = "选择"
            panel.begin { response in
                if response == .OK {
                    completion(panel.url)
                } else {
                    completion(nil)
                }
            }
        }
    }
}
