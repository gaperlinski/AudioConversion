//
//  AudioConversionSession.swift
//  VideoHashing
//
//  Created by Grzegorz Aperliński on 19/01/2020.
//  Copyright © 2020 Grzegorz Aperlinski. All rights reserved.
//

import AVFoundation

protocol AudioConversionSessionDelegate: AnyObject {
    func didFinishWriting(to url: URL)
}

class AudioConversionSession: NSObject {
    
    weak var delegate: AudioConversionSessionDelegate?
    
    private var firstAudioBuffer = true
    private var session: AVCaptureSession!
    private var writer: AVAssetWriter!
    private var converter: LBAudioConverter!
    private var appendedBytes = 0
    private let writingQueue = DispatchQueue(label: "com.gaperlinski.writer.lock")
    private let sampleRate: Int32 = 44_100
    private var receivedSamples = 0
    
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: // The user has previously granted access to the camera.
            DispatchQueue.main.async {
                self.setupCaptureSession()
            }
        case .notDetermined: // The user has not yet been asked for camera access.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupCaptureSession()
                    }
                }
            }
            
        case .denied: // The user has previously denied access.
            return
            
        case .restricted: // The user can't grant access due to restrictions.
            return
        @unknown default:
            fatalError()
        }
    }
    
    private func setupCaptureSession() {
        session = AVCaptureSession()
        converter = createConverter()
        converter.delegate = self
        
        let microphone = AVCaptureDevice.default(.builtInMicrophone,
                                                  for: .audio,
                                                  position: .unspecified)
        do {
            let input = try AVCaptureDeviceInput(device: microphone!)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.gaperlinski.audio-capture.lock"))
            
            session.addInput(input)
            session.addOutput(output)
            
        } catch {
            
        }
        
        firstAudioBuffer = true
        appendedBytes = 0
        receivedSamples = 0
        
        writer = createWriter()
        session.startRunning()
    }

    func finish() {
        writingQueue.async {
            self.session.stopRunning()
            let outputURL = self.writer.outputURL
            self.writer.finishWriting {
                self.writer = nil
                self.converter.stopEncoding {
                    self.converter = nil
                }
                print("Appended bytes:", self.appendedBytes)
                self.delegate?.didFinishWriting(to: outputURL)
            }
        }
    }
    
    private func createConverter() -> LBAudioConverter {
        let asbd = AudioStreamBasicDescription(
            mSampleRate: 44_100,
            mFormatID: kAudioFormatMPEG4AAC,
            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
            mBytesPerPacket: 0,
            mFramesPerPacket: 1024,
            mBytesPerFrame: 0,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 0,
            mReserved: 0)

        return LBAudioConverter(convertingTo: asbd)
    }
    
    private func createWriter() -> AVAssetWriter? {
        do {
            let url: URL = URL(fileURLWithPath: NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]).appendingPathComponent(UUID().uuidString + ".mp4")
            return try AVAssetWriter(outputURL: url, fileType: .mp4)
        } catch {
            print(error)
        }
        return nil
    }
    
    private func getWriterInput(formatHint: CMFormatDescription?) -> AVAssetWriterInput? {
        guard writer.inputs.isEmpty else {
            return writer.inputs.first
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: formatHint)
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        return input
    }
}

extension AudioConversionSession: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        converter.append(sampleBuffer)
    }
}

extension AudioConversionSession: LBAudioConverterDelegate {
    func converter(_ converter: LBAudioConverter!, convertedSampleBuffer: CMSampleBuffer!, trimDurationAtStart trimDuration: Int32) {
        if receivedSamples < 50 { // arbitrary count to wait for getting larger sample buffers
            receivedSamples += 1
            return
        }
        appendSampleBuffer(convertedSampleBuffer, trimDuration: trimDuration)
    }
}

extension AudioConversionSession {
    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, trimDuration: Int32) {
        writingQueue.async {
            
            guard let writer = self.writer,
                let input = self.getWriterInput(formatHint: CMSampleBufferGetFormatDescription(sampleBuffer)) else { return }
            
            switch writer.status {
            case .unknown:
                writer.startWriting()
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            default:
                break
            }
            
            if input.isReadyForMoreMediaData {
                if self.firstAudioBuffer {
                    self.firstAudioBuffer = false
                    let primingDuration = CMTime(value: CMTimeValue(trimDuration), timescale: self.sampleRate)
                    self.primeSample(sampleBuffer, primingDuration: primingDuration)
                    
                }
                if input.append(sampleBuffer) {
                    self.appendedBytes += sampleBuffer.bytesCount
                    // Uncomment to print appended bytes
//                    for bytes in sampleBuffer.data {
//                        print(bytes, terminator: " ")
//                    }
                }
            }
        }
    }
    
    private func primeSample(_ sampleBuffer: CMSampleBuffer, primingDuration: CMTime) {
        var attachmentMode: CMAttachmentMode = 0
        let trimDuration = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, attachmentModeOut: &attachmentMode)
        if (trimDuration == nil) {
            CMSetAttachment(sampleBuffer,
                            key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                            value: CMTimeCopyAsDictionary(primingDuration, allocator: kCFAllocatorDefault),
                            attachmentMode: kCMAttachmentMode_ShouldPropagate)
        }
    }
}
