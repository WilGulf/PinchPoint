//
//  ContentView.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var model = FrameHandler()
    
    var body: some View {
        VStack {
            Text("Hello World")
        }
    }
}

#Preview {
    ContentView()
}
