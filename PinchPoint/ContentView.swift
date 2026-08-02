//
//  ContentView.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//
let VERSION_MAJOR = 0
let VERSION_MINOR = 2
let VERSION_PATCH = 0


import SwiftUI

struct ContentView: View {
    @StateObject private var model = FrameHandler()
    
    var body: some View {
        VStack {
            Text("Hello World")
            
            if let frame = model.frame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: -1)
                    .frame(width: 320, height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 5)
            }
        }
    }
}

#Preview {
    ContentView()
}
