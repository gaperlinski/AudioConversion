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
    
    private var session: AVCaptureSession!
    private var writer: AVAssetWriter!
//    private var converter: LBAudioConverter!
    private var converter: AudioConverter!
    private var receivedAudioBuffers = 0
    private let writingQueue = DispatchQueue(label: "com.gaperlinski.writer.lock")
    
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
        
        writer = createWriter()
        session.startRunning()
        converter.startRunning()
    }

    func finish() {
        session.stopRunning()
        let outputURL = writer.outputURL
        writer.finishWriting { [weak self] in
            self?.receivedAudioBuffers = 0
            self?.writer = nil
            self?.converter.stopRunning()
//            self?.converter.stopEncoding {
//                self?.converter = nil
//            }
            self?.delegate?.didFinishWriting(to: outputURL)
        }
    }
    
    private func createConverter() -> AudioConverter {
//        let asbd = AudioStreamBasicDescription(
//            mSampleRate: 44_100,
//            mFormatID: kAudioFormatMPEG4AAC,
//            mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
//            mBytesPerPacket: 0,
//            mFramesPerPacket: 1024,
//            mBytesPerFrame: 0,
//            mChannelsPerFrame: 2,
//            mBitsPerChannel: 0,
//            mReserved: 0)

        return AudioConverter()
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
//        converter.append(sampleBuffer)
        converter.encodeSampleBuffer(sampleBuffer)
    }
}

//extension AudioConversionSession: LBAudioConverterDelegate {
//    func converter(_ converter: LBAudioConverter!, convertedSampleBuffer: CMSampleBuffer!, trimDurationAtStart trimDuration: Int32) {
//        let primingDuration = CMTime(value: CMTimeValue(trimDuration), timescale: 44_100)
//        appendSampleBuffer(convertedSampleBuffer,  primingDuration: primingDuration)
//    }
//}

extension AudioConversionSession: AudioConverterDelegate {
    func didSetFormatDescription(audio formatDescription: CMFormatDescription?) {
        // nop
    }
    func sampleOutput(_ sampleBuffer: CMSampleBuffer) {
        appendSampleBuffer(sampleBuffer)
    }
}

extension AudioConversionSession {
    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
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
                self.primeSampleBufferIfNeeded(sampleBuffer)
                let result = input.append(sampleBuffer)
                print(result)
            }
        }
    }
    
    private func primeSampleBufferIfNeeded(_ sampleBuffer: CMSampleBuffer) {
        // TODO
        if self.receivedAudioBuffers < 2 {
            let primingDuration = CMTimeMake(value: 1024, timescale: 44_100)
            CMSetAttachment(sampleBuffer,
                            key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                            value: CMTimeCopyAsDictionary(primingDuration, allocator: kCFAllocatorDefault),
                            attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
            self.receivedAudioBuffers += 1
        } else if self.receivedAudioBuffers == 2 {
            let primingDuration = CMTimeMake(value: 64, timescale: 44_100)
            CMSetAttachment(sampleBuffer,
                            key: kCMSampleBufferAttachmentKey_TrimDurationAtStart,
                            value: CMTimeCopyAsDictionary(primingDuration, allocator: kCFAllocatorDefault),
                            attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
            self.receivedAudioBuffers += 1
        }
    }
}
