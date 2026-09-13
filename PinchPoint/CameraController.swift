//
//  Camera.swift
//  PinchPoint
//
//  Created by Wilgot Ulfstedt on 2026-07-24.
//

import AVFoundation
import Combine
import CoreImage
import AppKit

class FrameHandler: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var frame: CGImage?
    private let context = CIContext()
    
    private let handTracker = HandTracker()
    private var permissionGranted = false
    
    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var videoOutput: AVCaptureVideoDataOutput?
    
    private var captureRunning: Bool = false
    
    override init () {
        super.init()
        self.checkPermission()
    }
    
    func isRunning() -> Bool {
        return captureRunning
    }
    
    func handlerStop() {
        sessionQueue.async {
            self.handTracker.cursorStop()
            
            var attempt = 0
            while self.handTracker.isRunning() {
                self.handTracker.cursorStop()
                
                attempt += 1
                if attempt > 25 {
                    DispatchQueue.main.async {
                        NSApplication.shared.terminate(nil)
                    }
                }
            }
            
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
            }

            for input in self.captureSession.inputs {
                self.captureSession.removeInput(input)
            }
            
            if let videoOutput = self.videoOutput {
                videoOutput.setSampleBufferDelegate(nil, queue: nil)
                self.captureSession.removeOutput(videoOutput)
                self.videoOutput = nil
            }

            DispatchQueue.main.async {
                self.frame = nil
            }
        }
        
        captureRunning = false
    }
    
    func handlerStart() {
        guard !self.captureSession.isRunning else { return }
        guard self.videoOutput == nil else { return }
        
        self.checkPermission()
    }
    
    func setupCaptureSession() {
        let videoOutput = AVCaptureVideoDataOutput()
        
        guard permissionGranted else { return }
        guard let videoDevice = AVCaptureDevice.default(for: .video) else { return }
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice) else { return }
        guard captureSession.canAddInput(videoDeviceInput) else { return }
        captureSession.addInput(videoDeviceInput)
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "samplebuffer.queue"))
        captureSession.addOutput(videoOutput)
        self.videoOutput = videoOutput
        
        // Latency (.hd1280x720) or accuracy (.high)
        captureSession.sessionPreset = .hd1280x720
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connectio: AVCaptureConnection
    ) {
        handTracker.process(sampleBuffer)
        
        guard let cgImage = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else { return }
        DispatchQueue.main.async { [unowned self] in
            self.frame = cgImage
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        
        return cgImage
    }
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.permissionGranted = true
            
            sessionQueue.async { [unowned self] in
                self.setupCaptureSession()
                self.captureSession.startRunning()
                handTracker.cursorStart()
                captureRunning = true
            }
        case .notDetermined:
            self.requestPermission()
        default:
            self.permissionGranted = false
        }
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
            print("Permission", granted)
            self.permissionGranted = granted
            if granted {
                checkPermission()
            }
        }
    }
}
