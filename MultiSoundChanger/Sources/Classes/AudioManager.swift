//
//  AudioManager.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 15.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import AudioToolbox
import Foundation

// MARK: - DeviceConfig

private struct DeviceConfig: Codable {
    var boost: Float
    var stepSize: Float
}

// MARK: - Protocols

protocol AudioManager: class {
    func getDefaultOutputDevice() -> AudioDeviceID
    func getOutputDevices() -> [AudioDeviceID: String]?
    func selectDevice(deviceID: AudioDeviceID)
    func getSelectedDeviceVolume() -> Float?
    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float)
    func isSelectedDeviceMuted() -> Bool
    func isSelectedDeviceAggregate() -> Bool
    func toggleMute()
    func isBoostableDevice(deviceID: AudioDeviceID) -> Bool
    func getDeviceBoost(deviceID: AudioDeviceID) -> Float
    func setDeviceBoost(deviceID: AudioDeviceID, boost: Float)
    func getDeviceStepSize(deviceID: AudioDeviceID) -> Float
    func setDeviceStepSize(deviceID: AudioDeviceID, stepSize: Float)
    func reloadDevices()

    var isMuted: Bool { get }
    var onDeviceListChanged: (() -> Void)? { get set }
}

// MARK: - MasterControlDevice

private struct MasterControlDevice {
    var volume: Float = 0.0
}

// MARK: - Device list change listener (C callback required by AudioObjectAddPropertyListener)

private func audioDeviceListChangedCallback(
    _ objectID: AudioObjectID,
    _ numAddresses: UInt32,
    _ addresses: UnsafePointer<AudioObjectPropertyAddress>,
    _ clientData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let ptr = clientData else { return noErr }
    let manager = Unmanaged<AudioManagerImpl>.fromOpaque(ptr).takeUnretainedValue()
    DispatchQueue.main.async { manager.scheduleDeviceListReload() }
    return noErr
}

// MARK: - Implementation

final class AudioManagerImpl: AudioManager {
    private let audio: Audio = AudioImpl()
    private var devices: [AudioDeviceID: String]?
    private var selectedDevice: AudioDeviceID?
    private var deviceBoosts: [AudioDeviceID: Float] = [:]
    private var deviceStepSizes: [AudioDeviceID: Float] = [:]
    private var masterControl = MasterControlDevice()
    var onDeviceListChanged: (() -> Void)?
    private var pendingReload: DispatchWorkItem?

    private static var settingsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("MultiSoundChanger", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("device-settings.json")
    }

    private static var deviceListPropertyAddress = AudioObjectPropertyAddress(
        mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
        mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
        mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMaster)
    )

    init() {
        devices = audio.getOutputDevices()
        if let devices = devices {
            for deviceID in devices.keys where !audio.isAggregateDevice(deviceID: deviceID) {
                deviceBoosts[deviceID] = 0.0
                deviceStepSizes[deviceID] = 1.0
            }
        }
        loadSettings()
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &AudioManagerImpl.deviceListPropertyAddress,
            audioDeviceListChangedCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
        printDevices()
    }

    deinit {
        AudioObjectRemovePropertyListener(
            AudioObjectID(kAudioObjectSystemObject),
            &AudioManagerImpl.deviceListPropertyAddress,
            audioDeviceListChangedCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )
    }

    fileprivate func scheduleDeviceListReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reloadDevices()
            self?.onDeviceListChanged?()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    func reloadDevices() {
        devices = audio.getOutputDevices()
        if let devices = devices {
            for deviceID in devices.keys where !audio.isAggregateDevice(deviceID: deviceID) {
                if deviceBoosts[deviceID] == nil { deviceBoosts[deviceID] = 0.0 }
                if deviceStepSizes[deviceID] == nil { deviceStepSizes[deviceID] = 1.0 }
            }
        }
        loadSettings()
        printDevices()
    }

    private func loadSettings() {
        guard let devices = devices,
              let data = try? Data(contentsOf: AudioManagerImpl.settingsFileURL),
              let saved = try? JSONDecoder().decode([String: DeviceConfig].self, from: data) else { return }
        let nameToID = Dictionary(uniqueKeysWithValues: devices.map { ($1, $0) })
        for (name, config) in saved {
            guard let deviceID = nameToID[name],
                  !audio.isAggregateDevice(deviceID: deviceID) else { continue }
            deviceBoosts[deviceID] = config.boost
            deviceStepSizes[deviceID] = config.stepSize
        }
    }

    private func saveSettings() {
        guard let devices = devices else { return }
        var settings: [String: DeviceConfig] = [:]
        for (deviceID, name) in devices where !audio.isAggregateDevice(deviceID: deviceID) {
            settings[name] = DeviceConfig(
                boost: deviceBoosts[deviceID] ?? 0.0,
                stepSize: deviceStepSizes[deviceID] ?? 1.0
            )
        }
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: AudioManagerImpl.settingsFileURL, options: .atomic)
        }
    }

    func getDefaultOutputDevice() -> AudioDeviceID {
        return audio.getDefaultOutputDevice()
    }

    func getOutputDevices() -> [AudioDeviceID: String]? {
        return devices
    }

    func selectDevice(deviceID: AudioDeviceID) {
        selectedDevice = deviceID
        audio.setOutputDevice(newDeviceID: deviceID)
        masterControl.volume = readHardwareVolume(for: deviceID) ?? 0.0
        Logger.debug(Constants.InnerMessages.selectDevice(deviceID: String(deviceID)))
    }

    func getSelectedDeviceVolume() -> Float? {
        guard selectedDevice != nil else { return nil }
        return masterControl.volume
    }

    private func readHardwareVolume(for deviceID: AudioDeviceID) -> Float? {
        if audio.isAggregateDevice(deviceID: deviceID) {
            for device in audio.getAggregateDeviceSubDeviceList(deviceID: deviceID) {
                if audio.isOutputDevice(deviceID: device) {
                    return audio.getDeviceVolume(deviceID: device).max()
                }
            }
            return nil
        }
        return audio.getDeviceVolume(deviceID: deviceID).max()
    }

    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float) {
        guard let selectedDevice = selectedDevice else {
            return
        }
        Logger.debug("selected device " + Constants.InnerMessages.debugDevice(deviceID: String(selectedDevice), deviceName: devices?[selectedDevice] ?? "unknown"))
        masterControl.volume = masterChannelLevel

        let isMute = masterChannelLevel < Constants.muteVolumeLowerbound
            && leftChannelLevel < Constants.muteVolumeLowerbound
            && rightChannelLevel < Constants.muteVolumeLowerbound

        func apply(to device: AudioDeviceID) {
            let boost = deviceBoosts[device] ?? 0.0
            let stepSize = deviceStepSizes[device] ?? 1.0
            audio.setDeviceVolume(
                deviceID: device,
                masterChannelLevel: (masterChannelLevel * stepSize + boost).clamped(to: 0...1),
                leftChannelLevel: (leftChannelLevel * stepSize + boost).clamped(to: 0...1),
                rightChannelLevel: (rightChannelLevel * stepSize + boost).clamped(to: 0...1)
            )
            audio.setDeviceMute(deviceID: device, isMute: isMute)
        }

        if audio.isAggregateDevice(deviceID: selectedDevice) {
            for device in audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice) {
                apply(to: device)
            }
        } else {
            apply(to: selectedDevice)
        }
    }
    
    func isBoostableDevice(deviceID: AudioDeviceID) -> Bool {
        return !audio.isAggregateDevice(deviceID: deviceID)
    }

    func getDeviceBoost(deviceID: AudioDeviceID) -> Float {
        return deviceBoosts[deviceID] ?? 0.0
    }

    func setDeviceBoost(deviceID: AudioDeviceID, boost: Float) {
        deviceBoosts[deviceID] = boost
        saveSettings()
        if let v = getSelectedDeviceVolume() {
            setSelectedDeviceVolume(masterChannelLevel: v, leftChannelLevel: v, rightChannelLevel: v)
        }
    }

    func getDeviceStepSize(deviceID: AudioDeviceID) -> Float {
        return deviceStepSizes[deviceID] ?? 1.0
    }

    func setDeviceStepSize(deviceID: AudioDeviceID, stepSize: Float) {
        deviceStepSizes[deviceID] = stepSize
        saveSettings()
        if let v = getSelectedDeviceVolume() {
            setSelectedDeviceVolume(masterChannelLevel: v, leftChannelLevel: v, rightChannelLevel: v)
        }
    }

    func setSelectedDeviceMute(isMute: Bool) {
        guard let selectedDevice = selectedDevice else {
            return
        }
        
        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)
            
            for device in aggregatedDevices {
                audio.setDeviceMute(deviceID: device, isMute: isMute)
            }
        } else {
            audio.setDeviceMute(deviceID: selectedDevice, isMute: isMute)
        }
    }
    
    func isSelectedDeviceAggregate() -> Bool {
        guard let selectedDevice = selectedDevice else { return false }
        return audio.isAggregateDevice(deviceID: selectedDevice)
    }

    func isSelectedDeviceMuted() -> Bool {
        guard let selectedDevice = selectedDevice else {
            return false
        }
        
        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)
            
            guard let device = aggregatedDevices.first else {
                return false
            }
            
            return audio.isDeviceMuted(deviceID: device)
        } else {
            return audio.isDeviceMuted(deviceID: selectedDevice)
        }
    }
    
    func toggleMute() {
        if isSelectedDeviceMuted() {
            setSelectedDeviceMute(isMute: false)
            let volume = getSelectedDeviceVolume() ?? 0
            setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)
        } else {
            setSelectedDeviceMute(isMute: true)
        }
    }
    
    var isMuted: Bool {
        return isSelectedDeviceMuted()
    }
    
    private func printDevices() {
        guard let devices = devices else {
            return
        }
        Logger.debug(Constants.InnerMessages.outputDevices)
        for device in devices {
            Logger.debug(Constants.InnerMessages.debugDevice(deviceID: String(device.key), deviceName: device.value))
        }
    }
}
