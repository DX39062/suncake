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
    
    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(sourceStore)
        }
    }
}
