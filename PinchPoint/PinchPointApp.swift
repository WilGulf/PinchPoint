//
//  PinchPointApp.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import SwiftUI

@main
struct PinchPointApp: App {
    @StateObject private var model = FrameHandler()
    
    var body: some Scene {
        Window("Settings", id: "settings-view") {
            ContentView()
                .environmentObject(model)
        }
        
        MenuBarExtra("PinchPoint", systemImage: "hand.pinch.fill") {
            MenuBarContentView()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.menu)
        
    }
}
