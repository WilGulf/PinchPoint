//
//  ContentView.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import SwiftUI

struct PreviewView: View {
    @EnvironmentObject var model: FrameHandler
    
    var body: some View {
        VStack() {
            if let frame = model.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: -1)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                ContentUnavailableView("No Camera Feed", systemImage: "photo.badge.exclamationmark")
            }
            
            Button(model.isRunning() ? "Stop" : "Start") {
                if model.isRunning(){
                    model.handlerStop()
                } else {
                    model.handlerStart()
                }
            }
        }
        .padding()
    }
}

struct GeneralView: View {
    var body: some View {
        Text("Hello World")
    }
}

struct AboutView: View {
    var body: some View {
        Text("PinchPoint")
    }
}

struct ContentView: View {
    @EnvironmentObject var model: FrameHandler
        
    var body: some View {
        TabView() {
            Tab("Preview", systemImage: "hand.pinch") {
                PreviewView().environmentObject(model)
            }
            Tab("General", systemImage: "gear") {
                GeneralView()
            }
            Tab("About", systemImage: "info.circle") {
                AboutView()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject var model: FrameHandler
    
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack {
            Text("PinchPoint")
                .font(.headline)
            
            Button(model.isRunning() ? "Stop" : "Start") {
                if (model.isRunning()) {
                    model.handlerStop()
                } else {
                    model.handlerStart()
                }
            }
            
            Button("Settings") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "settings-view")
            }
            
            Divider()
            
            Button("Quit PinchPoint") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

#Preview {
    ContentView()
}
