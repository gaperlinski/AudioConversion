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
        DispatchQueue.main.async {
            let activityViewController = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            self.present(activityViewController, animated: true, completion: nil)
        }
    }
}
