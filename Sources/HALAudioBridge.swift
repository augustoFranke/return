import AudioToolbox
import CoreAudio
import CReturnAudio
import Foundation

private let inputAvailableCallback: AURenderCallback = { userData, _, timestamp, _, frameCount, _ in
    return Unmanaged<HALAudioBridge>.fromOpaque(userData)
        .takeUnretainedValue()
        .captureInput(timestamp: timestamp, frameCount: frameCount)
}

private let outputRenderCallback: AURenderCallback = { userData, _, _, _, frameCount, ioData in
    guard let ioData else { return kAudio_ParamError }
    return Unmanaged<HALAudioBridge>.fromOpaque(userData)
        .takeUnretainedValue()
        .renderOutput(frameCount: frameCount, ioData: ioData)
}

final class HALAudioBridge {
    struct Diagnostics {
        let inputDeviceName: String
        let outputDeviceName: String
        let inputBufferFrames: UInt32
        let outputBufferFrames: UInt32
        let bridgeTargetFrames: UInt32
        let sampleRate: Double
    }

    enum BridgeError: LocalizedError {
        case audioStatus(operation: String, status: OSStatus)
        case missingDefaultDevice(String)
        case incompatibleSampleRates(input: Double, output: Double)
        case allocationFailed
        case frameCountTooLarge(UInt32)

        var errorDescription: String? {
            switch self {
            case let .audioStatus(operation, status):
                return "\(operation) failed (OSStatus \(status.fourCharacterCode))"
            case let .missingDefaultDevice(kind):
                return "No default \(kind) audio device is available"
            case let .incompatibleSampleRates(input, output):
                return "Input and output sample rates differ (\(input) Hz vs \(output) Hz)"
            case .allocationFailed:
                return "Could not allocate the low-latency audio bridge"
            case let .frameCountTooLarge(frames):
                return "Audio device requested an unsupported \(frames)-frame slice"
            }
        }
    }

    private var inputUnit: AudioUnit?
    private var outputUnit: AudioUnit?
    private var ring: OpaquePointer?
    private var inputScratch: UnsafeMutablePointer<Float>?
    private var outputScratch: UnsafeMutablePointer<Float>?
    private var originalDeviceBufferFrames: [AudioDeviceID: UInt32] = [:]
    private let maximumFrames: UInt32 = 8_192

    private(set) var diagnostics: Diagnostics?

    deinit {
        stop()
    }

    func start(volume: Float) throws {
        stop()

        do {
            guard let inputDevice = defaultAudioDevice(for: kAudioHardwarePropertyDefaultInputDevice) else {
                throw BridgeError.missingDefaultDevice("input")
            }
            guard let outputDevice = defaultAudioDevice(for: kAudioHardwarePropertyDefaultOutputDevice) else {
                throw BridgeError.missingDefaultDevice("output")
            }

            let inputRate = nominalSampleRate(inputDevice)
            let outputRate = nominalSampleRate(outputDevice)
            guard abs(inputRate - outputRate) < 0.5 else {
                throw BridgeError.incompatibleSampleRates(input: inputRate, output: outputRate)
            }

            let inputFrames = try setBufferFrames(inputDevice, preferredFrames: 32)
            let outputFrames = try setBufferFrames(outputDevice, preferredFrames: 32)
            let targetFrames = max(inputFrames, outputFrames) * 4

            guard let ring = return_audio_ring_create(16_384, targetFrames) else {
                throw BridgeError.allocationFailed
            }
            self.ring = ring
            return_audio_ring_set_volume(ring, volume)

            inputScratch = .allocate(capacity: Int(maximumFrames))
            outputScratch = .allocate(capacity: Int(maximumFrames))
            inputScratch?.initialize(repeating: 0, count: Int(maximumFrames))
            outputScratch?.initialize(repeating: 0, count: Int(maximumFrames))

            inputUnit = try makeHALUnit(device: inputDevice, inputEnabled: true, outputEnabled: false)
            outputUnit = try makeHALUnit(device: outputDevice, inputEnabled: false, outputEnabled: true)

            try configureInputUnit(sampleRate: inputRate, maximumFrames: inputFrames)
            try configureOutputUnit(sampleRate: outputRate, maximumFrames: outputFrames)

            try check(AudioUnitInitialize(inputUnit!), "Initialize input HAL")
            try check(AudioUnitInitialize(outputUnit!), "Initialize output HAL")
            try check(AudioOutputUnitStart(inputUnit!), "Start input HAL")
            try check(AudioOutputUnitStart(outputUnit!), "Start output HAL")

            diagnostics = Diagnostics(
                inputDeviceName: deviceName(inputDevice),
                outputDeviceName: deviceName(outputDevice),
                inputBufferFrames: inputFrames,
                outputBufferFrames: outputFrames,
                bridgeTargetFrames: targetFrames,
                sampleRate: inputRate
            )
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if let outputUnit {
            AudioOutputUnitStop(outputUnit)
            AudioUnitUninitialize(outputUnit)
            AudioComponentInstanceDispose(outputUnit)
        }
        if let inputUnit {
            AudioOutputUnitStop(inputUnit)
            AudioUnitUninitialize(inputUnit)
            AudioComponentInstanceDispose(inputUnit)
        }
        outputUnit = nil
        inputUnit = nil

        if let ring {
            return_audio_ring_destroy(ring)
        }
        ring = nil

        inputScratch?.deallocate()
        outputScratch?.deallocate()
        inputScratch = nil
        outputScratch = nil
        diagnostics = nil
        restoreDeviceBufferFrames()
    }

    func setVolume(_ volume: Float) {
        return_audio_ring_set_volume(ring, volume)
    }

    func runtimeStats() -> (
        fill: UInt32, underflows: UInt64, overflows: UInt64,
        shortened: UInt64, stretched: UInt64,
        writeCalls: UInt64, writtenFrames: UInt64, renderCalls: UInt64, renderedFrames: UInt64,
        maximumWrite: UInt32, maximumRender: UInt32
    ) {
        let stats = return_audio_ring_stats(ring)
        return (
            stats.fill_frames,
            stats.underflows,
            stats.overflows,
            stats.shortened_reads,
            stats.stretched_reads,
            stats.write_calls,
            stats.written_frames,
            stats.render_calls,
            stats.rendered_frames,
            stats.maximum_write_frames,
            stats.maximum_render_frames
        )
    }

    fileprivate func captureInput(
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: UInt32
    ) -> OSStatus {
        guard frameCount <= maximumFrames, let inputUnit, let inputScratch, let ring else {
            return kAudio_ParamError
        }

        var bufferList = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: frameCount * UInt32(MemoryLayout<Float>.size),
                mData: inputScratch
            )
        )
        var flags: AudioUnitRenderActionFlags = []
        let status = AudioUnitRender(inputUnit, &flags, timestamp, 1, frameCount, &bufferList)
        guard status == noErr else { return status }

        return_audio_ring_write(ring, inputScratch, frameCount)
        return noErr
    }

    fileprivate func renderOutput(frameCount: UInt32, ioData: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        guard frameCount <= maximumFrames, let outputScratch, let ring else {
            return kAudio_ParamError
        }

        return_audio_ring_render(ring, outputScratch, frameCount)
        let buffers = UnsafeMutableAudioBufferListPointer(ioData)
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let channels = Int(buffer.mNumberChannels)
            if channels == 1 {
                data.update(from: outputScratch, count: Int(frameCount))
            } else {
                for frame in 0..<Int(frameCount) {
                    for channel in 0..<channels {
                        data[frame * channels + channel] = outputScratch[frame]
                    }
                }
            }
        }
        return noErr
    }

    private func makeHALUnit(
        device: AudioDeviceID,
        inputEnabled: Bool,
        outputEnabled: Bool
    ) throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw BridgeError.audioStatus(operation: "Find AUHAL component", status: kAudio_ParamError)
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), "Create AUHAL instance")
        guard let unit else { throw BridgeError.allocationFailed }

        do {
            var inputFlag: UInt32 = inputEnabled ? 1 : 0
            try setProperty(
                unit, kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input,
                element: 1, value: &inputFlag, operation: "Configure HAL input"
            )
            var outputFlag: UInt32 = outputEnabled ? 1 : 0
            try setProperty(
                unit, kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output,
                element: 0, value: &outputFlag, operation: "Configure HAL output"
            )
            var device = device
            try setProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, scope: kAudioUnitScope_Global,
                element: 0, value: &device, operation: "Select HAL device"
            )
            return unit
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    private func configureInputUnit(sampleRate: Double, maximumFrames: UInt32) throws {
        guard let inputUnit else { throw BridgeError.allocationFailed }
        var format = monoFloatFormat(sampleRate: sampleRate)
        try setProperty(
            inputUnit, kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output,
            element: 1, value: &format, operation: "Set input client format"
        )
        var callback = AURenderCallbackStruct(
            inputProc: inputAvailableCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setProperty(
            inputUnit, kAudioOutputUnitProperty_SetInputCallback, scope: kAudioUnitScope_Global,
            element: 0, value: &callback, operation: "Install input callback"
        )
        var maximumFrames = maximumFrames
        try setProperty(
            inputUnit, kAudioUnitProperty_MaximumFramesPerSlice, scope: kAudioUnitScope_Global,
            element: 0, value: &maximumFrames, operation: "Set input slice size"
        )
    }

    private func configureOutputUnit(sampleRate: Double, maximumFrames: UInt32) throws {
        guard let outputUnit else { throw BridgeError.allocationFailed }
        var format = stereoFloatFormat(sampleRate: sampleRate)
        try setProperty(
            outputUnit, kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Input,
            element: 0, value: &format, operation: "Set output client format"
        )
        var callback = AURenderCallbackStruct(
            inputProc: outputRenderCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )
        try setProperty(
            outputUnit, kAudioUnitProperty_SetRenderCallback, scope: kAudioUnitScope_Input,
            element: 0, value: &callback, operation: "Install output callback"
        )
        var maximumFrames = maximumFrames
        try setProperty(
            outputUnit, kAudioUnitProperty_MaximumFramesPerSlice, scope: kAudioUnitScope_Global,
            element: 0, value: &maximumFrames, operation: "Set output slice size"
        )
    }

    private func monoFloatFormat(sampleRate: Double) -> AudioStreamBasicDescription {
        floatFormat(sampleRate: sampleRate, channels: 1)
    }

    private func stereoFloatFormat(sampleRate: Double) -> AudioStreamBasicDescription {
        floatFormat(sampleRate: sampleRate, channels: 2)
    }

    private func floatFormat(sampleRate: Double, channels: UInt32) -> AudioStreamBasicDescription {
        AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size),
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private func setProperty<T>(
        _ unit: AudioUnit,
        _ property: AudioUnitPropertyID,
        scope: AudioUnitScope,
        element: AudioUnitElement,
        value: inout T,
        operation: String
    ) throws {
        let status = withUnsafeBytes(of: &value) { bytes in
            AudioUnitSetProperty(
                unit, property, scope, element, bytes.baseAddress!, UInt32(bytes.count)
            )
        }
        try check(status, operation)
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw BridgeError.audioStatus(operation: operation, status: status)
        }
    }

    private func defaultAudioDevice(for selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    private func setBufferFrames(_ device: AudioDeviceID, preferredFrames: UInt32) throws -> UInt32 {
        if originalDeviceBufferFrames[device] == nil {
            originalDeviceBufferFrames[device] = deviceBufferFrames(device)
        }

        var rangeAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSizeRange,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var range = AudioValueRange()
        var rangeSize = UInt32(MemoryLayout<AudioValueRange>.size)
        try check(
            AudioObjectGetPropertyData(device, &rangeAddress, 0, nil, &rangeSize, &range),
            "Read device buffer range"
        )

        var frames = UInt32(
            min(max(Double(preferredFrames), range.mMinimum), range.mMaximum).rounded(.up)
        )
        var frameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyBufferFrameSize,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        try check(
            AudioObjectSetPropertyData(
                device, &frameAddress, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &frames
            ),
            "Set device buffer"
        )
        return deviceBufferFrames(device) ?? frames
    }

    private func deviceBufferFrames(_ device: AudioDeviceID) -> UInt32? {
        scalarProperty(device, selector: kAudioDevicePropertyBufferFrameSize)
    }

    private func nominalSampleRate(_ device: AudioDeviceID) -> Double {
        scalarProperty(device, selector: kAudioDevicePropertyNominalSampleRate) ?? 0
    }

    private func scalarProperty<T>(
        _ device: AudioDeviceID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        var size = UInt32(MemoryLayout<T>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, pointer) == noErr else {
            return nil
        }
        return pointer.pointee
    }

    private func deviceName(_ device: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name) == noErr else {
            return "Unknown"
        }
        return (name?.takeUnretainedValue() as String?) ?? "Unknown"
    }

    private func restoreDeviceBufferFrames() {
        for (device, savedFrames) in originalDeviceBufferFrames {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyBufferFrameSize,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var frames = savedFrames
            AudioObjectSetPropertyData(
                device, &address, 0, nil,
                UInt32(MemoryLayout<UInt32>.size), &frames
            )
        }
        originalDeviceBufferFrames.removeAll()
    }
}

private extension OSStatus {
    var fourCharacterCode: String {
        let bigEndian = UInt32(bitPattern: self).bigEndian
        let bytes = withUnsafeBytes(of: bigEndian) { Array($0) }
        if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
            return "'\(String(bytes: bytes, encoding: .ascii) ?? "????")'"
        }
        return String(self)
    }
}
