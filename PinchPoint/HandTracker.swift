//
//  HandTracker.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import Vision
import AVFoundation
import AppKit
import Combine

final class HandTracker: NSObject {
    private var handPoseRequest = VNDetectHumanHandPoseRequest()
    private let visionQueue = DispatchQueue(label: "vision.handpose.queue")
    private let cursorQueue = DispatchQueue(label: "cursor.queue")

    let sizeX: CGFloat = (NSScreen.main?.frame.width ?? 0)
    let sizeY: CGFloat = (NSScreen.main?.frame.height ?? 0)
    
    private var lastInference: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    private var minInferenceInterval: CFTimeInterval =  1.0 / 25.0
    private var inferenceDurations: [CFTimeInterval] = []
    private let maxDurations = 30
    private var processesSicnceLastUpdate = 0
    
    private var cursorModeEnterCounter = 0
    private var cursorModeExitCounter = 0
    private let stableThreshold = 4
    private var cursorMode = false
    
    private var noHandCounter = 0
    private var noHand = false
    private let noHandThreshold = 30
    
    private var handScale: Double = 0
    private var handScaleArray: [Double] = []
    private let maxHandScaleEntries = 8
    
    private var clickUpCounter = 0
    private var clickDownCounter = 0
    private var clickCoolDown = false
    private let clickThreshold = 3
    private var click = false
    private var clickLock = false
    private var rightClick = false
    private var clickPositionBuffer: CGPoint = CGPoint(x: 0, y: 0)
    private var clickDownTime: CFAbsoluteTime = 0
    
    private var smoothedX: CGFloat = 0
    private var smoothedY: CGFloat = 0
    private let smoothingFactor: CGFloat = 0.8
    
    private var lastPosition: CGPoint = CGPoint(x: 0, y: 0)
    private var lastNormalizedPosition: CGPoint = CGPoint(x: 0, y: 0)
    private var hasInitializedPosition = false
    
    private let activeMinX: CGFloat = 0.2
    private let activeMaxX: CGFloat = 0.8
    private let activeMinY: CGFloat = 0.3
    private let activeMaxY: CGFloat = 0.85
    
    override init() {
        super.init()
        
        cursorQueue.async {
            while true {
                if self.cursorMode && !self.noHand {
                    self.smoothedX = (self.smoothedX * self.smoothingFactor) + (self.lastNormalizedPosition.x * (1 - self.smoothingFactor))
                    self.smoothedY = (self.smoothedY * self.smoothingFactor) + (self.lastNormalizedPosition.y * (1 - self.smoothingFactor))
                    let newLocation = CGPoint(x: (self.smoothedX) * self.sizeX, y: (self.smoothedY) * self.sizeY)
                    
                    DispatchQueue.main.async {
                        CGDisplayMoveCursorToPoint(CGMainDisplayID(), newLocation)
                    }
                }
                
                Thread.sleep(forTimeInterval: 1.0 / 60)
            }
        }
    }
    
    private var processLock = false
    func process(_ sampleBuffer: CMSampleBuffer) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastInference >= minInferenceInterval else { return }
        lastInference = now
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let request = handPoseRequest
        request.maximumHandCount = 1
        
        visionQueue.async { [weak self] in
            guard let self else { return }
            guard processLock == false else { return }
            processLock = true
            do {
                defer {
                    processLock = false
                    updateNoHand(handPresent: false)
                }
                
                let handler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    options: [:]
                )
                
                let startTime = CFAbsoluteTimeGetCurrent()
                try handler.perform([request])
                processLock = false
                let processDuration = CFAbsoluteTimeGetCurrent() - startTime
                if inferenceDurations.count >= maxDurations {
                    inferenceDurations.remove(at: 0)
                }
                inferenceDurations.append(processDuration)
                processesSicnceLastUpdate += 1
                
                guard let observations = request.results, !observations.isEmpty else { return }
                
                let best = observations.max(by: { $0.confidence < $1.confidence })
                if let best {
                    self.processHandObservation(best)
                } else { return }
            } catch {
                processLock = false
                print("[Vision][ERR] perform failed: \(error)")
            }
        }
        
        if processesSicnceLastUpdate >= maxDurations && inferenceDurations.count >= maxDurations {
            let sorted = inferenceDurations.sorted()
            let p90: Double = sorted[Int(round(Double((maxDurations)) * 0.9))]
            //print("p90: ", p90)
            minInferenceInterval = min(max(p90 * 1.3, 0.02), 0.1)
            processesSicnceLastUpdate = 0
        }
    }
    
    private func processHandObservation(_ obs: VNHumanHandPoseObservation) {
        
        do {
            let points = try obs.recognizedPoints(.all)
            
            func p(_ j: VNHumanHandPoseObservation.JointName) -> CGPoint? {
                if let rp = points[j], rp.confidence > 0.45 {
                    return CGPoint(x: CGFloat(1 - rp.location.x), y: CGFloat(1 - rp.location.y))
                }
                return nil
            }
            
            let wrist = p(.wrist)
            if wrist == nil {
                updateNoHand(handPresent: false)
            } else {
                updateNoHand(handPresent: true)
            }
            /*guard let wrist = p(.wrist) else {
                updateNoHand(handPresent: false)
                return
            }*/
            
            struct Finger { let tip: CGPoint?; let mcp: CGPoint? }
            let fingers: [Finger] = [
                Finger(tip: p(.thumbTip),  mcp: p(.thumbCMC)),
                Finger(tip: p(.indexTip),  mcp: p(.indexMCP)),
                Finger(tip: p(.middleTip), mcp: p(.middleMCP)),
                Finger(tip: p(.ringTip),   mcp: p(.ringMCP)),
                Finger(tip: p(.littleTip), mcp: p(.littleMCP))
            ]
            
            var extended: [Int] = []
            
            var amountNotNil = 0
            let count = 1...4
            for index in count {
                if fingers[index].mcp != nil {
                    amountNotNil += 1
                }
            }
            
            guard amountNotNil > 0 else { return }
            var center = CGPoint(x: 0, y: 0)
            center.x = ((fingers[1].mcp?.x ?? 0) + (fingers[2].mcp?.x ?? 0) + (fingers[3].mcp?.x ?? 0) + (fingers[4].mcp?.x ?? 0)) / CGFloat(amountNotNil)
            center.y = ((fingers[1].mcp?.y ?? 0) + (fingers[2].mcp?.y ?? 0) + (fingers[3].mcp?.y ?? 0) + (fingers[4].mcp?.y ?? 0)) / CGFloat(amountNotNil)
            
            for (i, f) in fingers.enumerated() {
                if let tip = f.tip, let mcp = f.mcp {
                    
                    let dm = hypot(tip.x - mcp.x, tip.y - mcp.y)
                    let dw = hypot(tip.x - center.x, tip.y - center.y)
                    
                    let isExtended: Bool
                    if i == 0 { // thumb
                        isExtended = dw > handScale / 1.15 /*0.20*/ && dm > handScale / 1.91 /*0.12*/
                    } else { // other fingers
                        isExtended = dw > handScale / 1.43 /*0.16*/ && dm > handScale / 2.87/*0.08*/
                    }
                    
                    if isExtended {
                        extended.append(i)
                    }
                }
            }
            
            if wrist != nil && fingers[2].mcp != nil {
                if handScaleArray.count >= maxHandScaleEntries {
                    handScaleArray.remove(at: 0)
                }
                handScaleArray.append(Double(hypot(wrist!.x - fingers[2].mcp!.x, wrist!.y - fingers[2].mcp!.y)))
                handScale = handScaleArray.reduce(0, +) / Double(handScaleArray.count)
                print(handScale)
            }
            
            if extended.count <= 2 && extended.contains(1) && extended.contains(0) {
                updateCursorMode(isOpen: true)
            }
            if extended.count <= 0 {
                updateCursorMode(isOpen: false)
            }
                
            if cursorMode {
                guard fingers[0].tip != nil && fingers[1].tip != nil else { return }
                var newPosition: CGPoint = lastPosition
                    
                let pinchDistance = hypot(fingers[0].tip!.x - fingers[1].tip!.x, fingers[0].tip!.y - fingers[1].tip!.y)
                //print(pinchDistance)
                if pinchDistance < handScale / 4.5 /*pinchDistance < 0.05*/ {
                    updatePinch(isPinch: true)
                    
                    if fingers[2].tip != nil {
                        let pinchDistance = hypot(fingers[1].tip!.x - fingers[2].tip!.x, fingers[1].tip!.y - fingers[2].tip!.y)
                        
                        if pinchDistance < 0.12 && extended.contains(2) {
                            if !clickLock {
                                rightClick = true
                            }
                        } else {
                            if !clickLock {
                            }
                                rightClick = false
                        }
                    }
                } else {
                    updatePinch(isPinch: false)
                }
                        
                //print("index + thumb")
                //newPosition = CGPoint(x: (fingers[1].tip!.x + fingers[0].tip!.x) / 2, y: (fingers[1].tip!.y + fingers[0].tip!.y) / 2)
                newPosition = fingers[0].tip!
                
                if hasInitializedPosition == false {
                    lastPosition = newPosition
                    //smoothedX = newPosition.x
                    //smoothedY = newPosition.y
                    hasInitializedPosition = true
                }
                    
                let distance = hypot(newPosition.x - lastPosition.x, newPosition.y - lastPosition.y)
                if distance <= 0.25 {
                    let normalizedX = (newPosition.x - activeMinX) / (activeMaxX - activeMinX)
                    let normalizedY = (newPosition.y - activeMinY) / (activeMaxY - activeMinY)
                    lastNormalizedPosition = CGPoint(x: normalizedX, y: normalizedY)
                    //print(lastNormalizedPosition)
                    lastPosition = newPosition
                }
                                
                //lastPosition = newPosition
                //print(lastPosition)
                
                //smoothedX = (smoothedX * smoothingFactor) + (lastNormalizedPosition.x * (1 - smoothingFactor))
                //smoothedY = (smoothedY * smoothingFactor) + (lastNormalizedPosition.y * (1 - smoothingFactor))
                let newLocation = CGPoint(x: (smoothedX) * sizeX, y: (smoothedY) * sizeY)
                
                /*DispatchQueue.main.async {
                    CGDisplayMoveCursorToPoint(CGMainDisplayID(), newLocation)
                }*/
                
                if click && !clickLock {
                    print("Down: ", rightClick)
                    clickPositionBuffer = newLocation
                    clickDownTime = CFAbsoluteTimeGetCurrent()
                    
                    if rightClick {
                        DispatchQueue.main.async {
                            CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: newLocation, mouseButton: .right)?.post(tap: .cghidEventTap)
                        }
                        
                        clickLock = true
                    } else {
                        DispatchQueue.main.async {
                            CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: newLocation, mouseButton: .left)?.post(tap: .cghidEventTap)
                        }
                        
                        clickLock = true
                    }
                    
                    updatePinch(isPinch: true)
                    clickCoolDown = true
                }
                
                if !click && !clickCoolDown {
                    let timeDown = CFAbsoluteTimeGetCurrent() - clickDownTime
                    if timeDown < 0.5 {
                        releaseMouseBtn(location: clickPositionBuffer)
                    } else {
                        releaseMouseBtn(location: newLocation)
                    }
                }
            }
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
            
            if cursorModeExitCounter >= 14 {
                cursorMode = false
                hasInitializedPosition = false
                print("Cursor Mode OFF")
            }
        }
    }
    
    private func releaseMouseBtn(location: CGPoint) {
        guard clickLock else { return }

        if rightClick {
            DispatchQueue.main.async {
                CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: location, mouseButton: .right)?.post(tap: .cghidEventTap)
            }
        } else {
            DispatchQueue.main.async {
                CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: location, mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
        
        print("Up: ", rightClick)
        clickLock = false
    }
    
    private func updateNoHand(handPresent: Bool) {
        if handPresent {
            noHand = false
            noHandCounter = 0
        } else {
            noHandCounter += 1
            
            if noHandCounter >= noHandThreshold {
                noHand = true
            }
        }
    }
    
    private func updatePinch(isPinch: Bool) {
        click = false
        
        if isPinch {
            clickUpCounter += 1
            clickDownCounter = 0
                
            if clickUpCounter >= clickThreshold {
                if !clickCoolDown {
                    click = true
                }
            }
        } else {
            clickDownCounter += 1
            clickUpCounter = 0
            
            if clickDownCounter >= clickThreshold {
                clickCoolDown = false
                //releaseMouseBtn(location: location)
            }
        }
    }
}
