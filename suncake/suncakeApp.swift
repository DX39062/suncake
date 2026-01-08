//
//  suncakeApp.swift
//  suncake
//
//  Created by yangxin on 2026/1/8.
//

internal import SwiftUI

@main
struct suncakeApp: App {
    @StateObject private var sourceStore = SourceStore()
    
    init() {
        print("DEBUG: 程序已启动，控制台正常工作")
    }

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sourceStore)
        }
    }
}
