//
//  ViewController.swift
//  VideoHashing
//
//  Created by Grzegorz Aperliński on 11/01/2020.
//  Copyright © 2020 Grzegorz Aperlinski. All rights reserved.
//

import AVKit

class ViewController: UIViewController {
    
    let audioConversionSession = AudioConversionSession()
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        audioConversionSession.delegate = self
    }

    @IBAction func didTapStart(_ sender: Any) {
        audioConversionSession.start()
    }
    
    @IBAction func didTapStop(_ sender: Any) {
        audioConversionSession.finish()
    }
}

extension ViewController: AudioConversionSessionDelegate {
    func didFinishWriting(to url: URL) {
        let asset = AVAsset(url: url)
        guard let assetReader = try? AVAssetReader(asset: asset) else {
            return
        }
        
        asset.loadValuesAsynchronously(forKeys: ["tracks"]) {
            var readBytes = 0
            
            guard let audioTrack = asset.tracks(withMediaType: .audio).first else { return }
            let audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
            assetReader.add(audioOutput)
            assetReader.startReading()
            
            while assetReader.status == .reading {
                if let sampleBuffer = audioOutput.copyNextSampleBuffer() {
                    if sampleBuffer.bytesCount > 0 {
//                      Uncomment to print bytes at beginning of file
//                        if readBytes == 0 {
//                            for bytes in sampleBuffer.data {
//                                print(bytes, terminator: " ")
//                            }
//                        }
                        readBytes += sampleBuffer.bytesCount
                    }
                }
            }
            
            print("Read bytes:", readBytes)
        }
    }
}
