//
//  FlickApp.swift
//  Flick
//
//  Created by 呆胶布 on 2026/4/16.
//

import SwiftUI

@main
struct FlickApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window - menu bar only app
        // Settings window is managed by AppDelegate
        Settings {
            EmptyView()
        }
    }
}
