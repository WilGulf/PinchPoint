//
//  HandTracker.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import Vision
import AVFoundation
import AppKit

final class HandTracker: NSObject {    
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(label: "vision.handpose.queue")
    
    private var lastInference: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private let minInferenceInterval: CFTimeInterval = 0.08
    
    private var cursorModeEnterCounter = 0
    private var cursorModeExitCounter = 0
    private var cursorMode = false
    
    /*private var openPalmCounter = 0
    private var closedPalmCounter = 0
    private var openPalm = false*/
    
    private let stableThreshold = 3
    
    private var smoothedX: CGFloat = 0
    private var smoothedY: CGFloat = 0
    private let smoothingFactor: CGFloat = 0.9
    
    private var lastPosition: CGPoint = CGPoint(x: 0, y: 0)
    private var hasInitializedPosition = false
    
    private let activeMinX: CGFloat = 0.2
    private let activeMaxX: CGFloat = 0.8
    private let activeMinY: CGFloat = 0.2
    private let activeMaxY: CGFloat = 0.85
    
    func process(_ sampleBuffer: CMSampleBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastInference >= minInferenceInterval else { return }
        lastInference = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = handPoseRequest
        request.maximumHandCount = 1
        
        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    options: [:]
                )
                try handler.perform([request])
                
                guard let observations = request.results, !observations.isEmpty else { return }
                
                let best = observations.max(by: { $0.confidence < $1.confidence })
                if let best {
                    self.processHandObservation(best)
                } else { return }
            } catch {
                print("[Vision][ERR] perform failed: \(error)")
            }
        }
    }
    
    private func processHandObservation(_ obs: VNHumanHandPoseObservation) {
        let sizeX: CGFloat = (NSScreen.main?.frame.width ?? 0)
        let sizeY: CGFloat = (NSScreen.main?.frame.height ?? 0)
        
        do {
            let points = try obs.recognizedPoints(.all)
            
            func p(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                if let rp = points[j], rp.confidence > 0.3 {
                    let normalizedX = (rp.location.x - activeMinX) / (activeMaxX - activeMinX)
                    let normalizedY = (rp.location.y - activeMinY) / (activeMaxY - activeMinY)
                    return CGPoint(x: CGFloat(1 - normalizedX), y: CGFloat(1 - normalizedY))
                }
                return nil
            }
            
            guard let wrist = p(.wrist) else { return }
            
            struct Finger { let tip: CGPoint?; let mcp: CGPoint? }
            let fingers: [Finger] = [
                Finger(tip: p(.thumbTip),  mcp: p(.thumbCMC)),
                Finger(tip: p(.indexTip),  mcp: p(.indexMCP)),
                Finger(tip: p(.middleTip), mcp: p(.middleMCP)),
                Finger(tip: p(.ringTip),   mcp: p(.ringMCP)),
                Finger(tip: p(.littleTip), mcp: p(.littleMCP))
            ]
            
            var extended: [Int] = []
            var tipPositions: [CGPoint] = []
            
            for (i, f) in fingers.enumerated() {
                if let tip = f.tip, let mcp = f.mcp {
                    let dm = hypot(tip.x - mcp.x, tip.y - mcp.y)
                    let dw = hypot(tip.x - wrist.x, tip.y - wrist.y)
                    
                    let isExtended: Bool
                    if i == 0 { // thumb
                        isExtended = dw > 0.20 && dm > 0.12
                    } else { // other fingers
                        isExtended = dw > 0.16 && dm > 0.08
                    }
                    
                    if isExtended {
                        extended.append(i)
                        tipPositions.append(tip)
                    }
                }
            }
            
            if extended.count <= 2 && extended.contains(1) && extended.contains(0) {
                updateCursorMode(isOpen: true)
            }
            if extended.count <= 1 {
                updateCursorMode(isOpen: false)
            }
            
            if extended.count >= 5 {
                updateOpenPalm(isOpen: true)
            } else {
                updateOpenPalm(isOpen: false)
            }
            
            if fingers[1].tip == nil && fingers[0].tip == nil { cursorMode = false }
            if cursorMode {
                var newPosition: CGPoint = lastPosition
                
                if fingers[0].tip != nil && fingers[1].tip != nil {
                    newPosition = CGPoint(x: (fingers[1].tip!.x + fingers[0].tip!.x) / 2, y: (fingers[1].tip!.y + fingers[0].tip!.y) / 2)
                } else if fingers[0].tip != nil {
                    newPosition = CGPoint(x: fingers[0].tip!.x, y: fingers[0].tip!.y)
                } else if fingers[1].tip != nil {
                    newPosition = CGPoint(x: fingers[1].tip!.x, y: fingers[1].tip!.y)
                }
                
                let distance = hypot(newPosition.x - lastPosition.x, newPosition.y - lastPosition.y)
                if distance <= 0.25 {
                    lastPosition = newPosition
                }
                if hasInitializedPosition == false {
                    lastPosition = newPosition
                    smoothedX = newPosition.x
                    smoothedY = newPosition.y
                    hasInitializedPosition = true
                }
                print(lastPosition)
            }
            
            smoothedX = (smoothedX * smoothingFactor) + (lastPosition.x * (1 - smoothingFactor))
            smoothedY = (smoothedY * smoothingFactor) + (lastPosition.y * (1 - smoothingFactor))
            let newLocation = CGPoint(x: (smoothedX) * sizeX, y: (smoothedY) * sizeY)
            CGDisplayMoveCursorToPoint(0, newLocation)
            
        } catch {
            print("[Vision][ERR] extract points failed: \(error)")
        }
    }
    
    private func updateCursorMode(isOpen: Bool) {
        if isOpen {
            cursorModeEnterCounter += 1
            cursorModeExitCounter = 0
            
            if cursorModeEnterCounter >= stableThreshold {
                cursorMode = true
            }
        } else {
            cursorModeExitCounter += 1
            cursorModeEnterCounter = 0
            
            if cursorModeExitCounter >= stableThreshold {
                cursorMode = false
                hasInitializedPosition = false
            }
        }
    }
    
    private func updateOpenPalm(isOpen: Bool) {
        
    }
}
