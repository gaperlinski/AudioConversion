import AVFoundation

public protocol AudioConverterDelegate: class {
    func sampleOutput(_ sampleBuffer: CMSampleBuffer)
}

// MARK: -
/**
 - seealse:
  - https://developer.apple.com/library/ios/technotes/tn2236/_index.html
 */
public class AudioConverter {
    enum Error: Swift.Error {
        case setPropertyError(id: AudioConverterPropertyID, status: OSStatus)
    }

    public static let minimumBitrate: UInt32 = 8 * 1024
    public static let defaultBitrate: UInt32 = 32 * 1024
    /// 0 means according to a input source
    public static let defaultChannels: UInt32 = 0
    /// 0 means according to a input source
    public static let defaultSampleRate: Double = 0
    public static let defaultMaximumBuffers: Int = 1
    public static let defaultBufferListSize: Int = AudioBufferList.sizeInBytes(maximumBuffers: 1)

    public weak var delegate: AudioConverterDelegate?
    public private(set) var isRunning: Atomic<Bool> = .init(false)

    var muted: Bool = false
    var bitrate: UInt32 = AudioConverter.defaultBitrate {
        didSet {
            guard bitrate != oldValue else {
                return
            }
            lockQueue.async {
                if let format = self._inDestinationFormat {
                    self.setBitrateUntilNoErr(self.bitrate * format.mChannelsPerFrame)
                }
            }
        }
    }
    var sampleRate: Double = AudioConverter.defaultSampleRate
    var actualBitrate: UInt32 = AudioConverter.defaultBitrate {
        didSet {
            print(actualBitrate)
        }
    }
    var channels: UInt32 = AudioConverter.defaultChannels
    var formatDescription: CMFormatDescription? 
    var lockQueue = DispatchQueue(label: "com.haishinkit.HaishinKit.AudioConverter.lock")
    var inSourceFormat: AudioStreamBasicDescription? {
        didSet {
            print("\(String(describing: self.inSourceFormat))")
            guard let inSourceFormat: AudioStreamBasicDescription = self.inSourceFormat else {
                return
            }
            let nonInterleaved: Bool = inSourceFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
            maximumBuffers = nonInterleaved ? Int(inSourceFormat.mChannelsPerFrame) : AudioConverter.defaultMaximumBuffers
            bufferListSize = nonInterleaved ? AudioBufferList.sizeInBytes(maximumBuffers: maximumBuffers) : AudioConverter.defaultBufferListSize
        }
    }

    private var maximumBuffers: Int = AudioConverter.defaultMaximumBuffers {
        didSet {
            guard oldValue != maximumBuffers else {
                return
            }
            currentBufferList.unsafeMutablePointer.deallocate()
            currentBufferList = AudioBufferList.allocate(maximumBuffers: maximumBuffers)
        }
    }
    private var filled = false
    private var bufferListSize: Int = AudioConverter.defaultBufferListSize
    private lazy var currentBufferList: UnsafeMutableAudioBufferListPointer = {
        AudioBufferList.allocate(maximumBuffers: maximumBuffers)
    }()
    private var _inDestinationFormat: AudioStreamBasicDescription?
    private var inDestinationFormat: AudioStreamBasicDescription {
        get {
            if _inDestinationFormat == nil {
                _inDestinationFormat = AudioStreamBasicDescription(
                    mSampleRate: 44_100,
                    mFormatID: kAudioFormatMPEG4AAC,
                    mFormatFlags: UInt32(MPEG4ObjectID.AAC_LC.rawValue),
                    mBytesPerPacket: 0,
                    mFramesPerPacket: 1024,
                    mBytesPerFrame: 0,
                    mChannelsPerFrame: 1,
                    mBitsPerChannel: 0,
                    mReserved: 0)
                CMAudioFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault,
                    asbd: &_inDestinationFormat!,
                    layoutSize: 0,
                    layout: nil,
                    magicCookieSize: 0,
                    magicCookie: nil,
                    extensions: nil,
                    formatDescriptionOut: &formatDescription
                )
            }
            return _inDestinationFormat!
        }
        set {
            _inDestinationFormat = newValue
        }
    }

    private var audioStreamPacketDescription = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0, mDataByteSize: 0) {
        didSet {
            audioStreamPacketDescriptionPointer = UnsafeMutablePointer<AudioStreamPacketDescription>(mutating: &audioStreamPacketDescription)
        }
    }
    private var audioStreamPacketDescriptionPointer: UnsafeMutablePointer<AudioStreamPacketDescription>?

    private let inputDataProc: AudioConverterComplexInputDataProc = {(
        converter: AudioConverterRef,
        ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
        ioData: UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?,
        inUserData: UnsafeMutableRawPointer?) in
        Unmanaged<AudioConverter>.fromOpaque(inUserData!).takeUnretainedValue().onInputDataForAudioConverter(
            ioNumberDataPackets,
            ioData: ioData,
            outDataPacketDescription: outDataPacketDescription
        )
    }

    deinit {
        currentBufferList.unsafeMutablePointer.deallocate()
    }

    private var _converter: AudioConverterRef?
    private var converter: AudioConverterRef {
        var status: OSStatus = noErr
        if _converter == nil {
            var inClassDescriptions = [
                AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleSoftwareAudioCodecManufacturer),
                AudioClassDescription(mType: kAudioEncoderComponentType, mSubType: kAudioFormatMPEG4AAC, mManufacturer: kAppleHardwareAudioCodecManufacturer)
            ]
            status = AudioConverterNewSpecific(
                &inSourceFormat!,
                &inDestinationFormat,
                UInt32(inClassDescriptions.count),
                &inClassDescriptions,
                &_converter
            )
            setBitrateUntilNoErr(bitrate * inDestinationFormat.mChannelsPerFrame)
        }
        if status != noErr {
            print("\(status)")
        }
        return _converter!
    }

    public func encodeSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let format: CMAudioFormatDescription = CMSampleBufferGetFormatDescription(sampleBuffer), isRunning.value else {
            return
        }

        if inSourceFormat == nil {
            inSourceFormat = CMAudioFormatDescriptionGetStreamBasicDescription( format)?.pointee
        }

        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: currentBufferList.unsafeMutablePointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: 0,
            blockBufferOut: &blockBuffer
        )

        if blockBuffer == nil {
            print("IllegalState for blockBuffer")
            return
        }

        if muted {
            for i in 0..<currentBufferList.count {
                memset(currentBufferList[i].mData, 0, Int(currentBufferList[i].mDataByteSize))
            }
        }

        convert(CMBlockBufferGetDataLength(blockBuffer!), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    @inline(__always)
    private func convert(_ dataBytesSize: Int, presentationTimeStamp: CMTime) {
        filled = false
        var finished: Bool = false
        repeat {
            var ioOutputDataPacketSize: UInt32 = 1

            let mamimumBuffers = Int(inSourceFormat!.mChannelsPerFrame)
            let outOutputData: UnsafeMutableAudioBufferListPointer = AudioBufferList.allocate(maximumBuffers: mamimumBuffers)
            for i in 0..<mamimumBuffers {
                outOutputData[i].mNumberChannels = inDestinationFormat.mChannelsPerFrame
                outOutputData[i].mDataByteSize = UInt32(dataBytesSize)
                outOutputData[i].mData = UnsafeMutableRawPointer.allocate(byteCount: dataBytesSize, alignment: 0)
            }

            let status: OSStatus = AudioConverterFillComplexBuffer(
                converter,
                inputDataProc,
                Unmanaged.passUnretained(self).toOpaque(),
                &ioOutputDataPacketSize,
                outOutputData.unsafeMutablePointer,
                nil
            )

            switch status {
            case noErr:
                let duration = CMTime(value:
                    CMTimeValue(_inDestinationFormat!.mFramesPerPacket),
                                      timescale: CMTimeScale(_inDestinationFormat!.mSampleRate))
                var timing = CMSampleTimingInfo(duration: duration,
                                                presentationTimeStamp: presentationTimeStamp,
                                                decodeTimeStamp: CMTime.invalid)
                var sampleSize: Int = Int(outOutputData.unsafeMutablePointer.pointee.mBuffers.mDataByteSize / ioOutputDataPacketSize)
                
                var outSampleBuffer: CMSampleBuffer?
                var status = CMSampleBufferCreate(
                    allocator: nil,
                    dataBuffer: nil,
                    dataReady: true,
                    makeDataReadyCallback: nil,
                    refcon: nil,
                    formatDescription: formatDescription,
                    sampleCount: CMItemCount(ioOutputDataPacketSize),
                    sampleTimingEntryCount: 1,
                    sampleTimingArray: &timing,
                    sampleSizeEntryCount: 1,
                    sampleSizeArray: &sampleSize,
                    sampleBufferOut: &outSampleBuffer)
                
                if status != noErr {
                    print("Failed to create sample buffer: \(status))")
                    return
                }
                
                status = CMSampleBufferSetDataBufferFromAudioBufferList(
                    outSampleBuffer!,
                    blockBufferAllocator: nil,
                    blockBufferMemoryAllocator: nil,
                    flags: 0,
                    bufferList: outOutputData.unsafeMutablePointer)
                
                if status != noErr {
                    print("Failed to set data buffer: \(status)")
                    return
                }
                
                delegate?.sampleOutput(outSampleBuffer!)
            case -1:
                finished = true
            default:
                finished = true
            }

            for i in 0..<outOutputData.count {
                free(outOutputData[i].mData)
            }

            free(outOutputData.unsafeMutablePointer)
        } while !finished
    }

    func invalidate() {
        lockQueue.async {
            self.inSourceFormat = nil
            self._inDestinationFormat = nil
            if let converter: AudioConverterRef = self._converter {
                AudioConverterDispose(converter)
            }
            self._converter = nil
        }
    }

    func onInputDataForAudioConverter(
        _ ioNumberDataPackets: UnsafeMutablePointer<UInt32>,
        ioData: UnsafeMutablePointer<AudioBufferList>,
        outDataPacketDescription: UnsafeMutablePointer<UnsafeMutablePointer<AudioStreamPacketDescription>?>?) -> OSStatus {
        guard !filled else {
            ioNumberDataPackets.pointee = 0
            return -1
        }

        memcpy(ioData, currentBufferList.unsafePointer, bufferListSize)
        ioNumberDataPackets.pointee = 1

        filled = true

        return noErr
    }

    private func setBitrateUntilNoErr(_ bitrate: UInt32) {
        do {
            try setProperty(id: kAudioConverterEncodeBitRate, data: bitrate * inDestinationFormat.mChannelsPerFrame)
            actualBitrate = bitrate
        } catch {
            if AudioConverter.minimumBitrate < bitrate {
                setBitrateUntilNoErr(bitrate - AudioConverter.minimumBitrate)
            } else {
                actualBitrate = AudioConverter.minimumBitrate
            }
        }
    }

    private func setProperty<T>(id: AudioConverterPropertyID, data: T) throws {
        guard let converter: AudioConverterRef = _converter else {
            return
        }
        let size = UInt32(MemoryLayout<T>.size)
        var buffer = data
        let status = AudioConverterSetProperty(converter, id, size, &buffer)
        guard status == 0 else {
            throw Error.setPropertyError(id: id, status: status)
        }
    }
}

extension AudioConverter: Running {
    // MARK: Running
    public func startRunning() {
        lockQueue.async {
            self.isRunning.mutate { $0 = true }
        }
    }

    public func stopRunning() {
        lockQueue.async {
            if let convert: AudioQueueRef = self._converter {
                AudioConverterDispose(convert)
                self._converter = nil
            }
            self.inSourceFormat = nil
            self.formatDescription = nil
            self._inDestinationFormat = nil
            self.isRunning.mutate { $0 = false }
        }
    }
}
