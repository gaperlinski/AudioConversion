//
//  CMSampleBuffer+Extension.swift
//  AudioConversion
//
//  Created by Grzegorz Aperliński on 24/02/2020.
//  Copyright © 2020 Grzegorz Aperlinski. All rights reserved.
//

import CoreMedia

extension CMSampleBuffer {
    var bytesCount: Int {
        let dataBuffer = CMSampleBufferGetDataBuffer(self)
        return dataBuffer.flatMap{ CMBlockBufferGetDataLength($0) } ?? 0
    }
    
    var data: Data {
        guard let dataBuffer = CMSampleBufferGetDataBuffer(self) else {
            return Data()
        }
        var length: Int = 0
        var buffer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &buffer) == noErr else {
            return Data()
        }
        return Data(bytes: buffer!, count: length)
    }
}
