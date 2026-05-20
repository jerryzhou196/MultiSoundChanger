//
//  AudioManager.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 15.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import AudioToolbox
import Foundation

// MARK: - Protocols

protocol AudioManager: class {
    func getDefaultOutputDevice() -> AudioDeviceID
    func getOutputDevices() -> [AudioDeviceID: String]?
    func selectDevice(deviceID: AudioDeviceID)
    func getSelectedDeviceVolume() -> Float?
    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float)
    func isSelectedDeviceMuted() -> Bool
    func toggleMute()
    func isBoostableDevice(deviceID: AudioDeviceID) -> Bool
    func getDeviceBoost(deviceID: AudioDeviceID) -> Float
    func setDeviceBoost(deviceID: AudioDeviceID, boost: Float)

    var isMuted: Bool { get }
}

// MARK: - Implementation

final class AudioManagerImpl: AudioManager {
    private let audio: Audio = AudioImpl()
    private let devices: [AudioDeviceID: String]?
    private var selectedDevice: AudioDeviceID?
    private var deviceBoosts: [AudioDeviceID: Float] = [:]

    init() {
        devices = audio.getOutputDevices()
        if let devices = devices {
            for deviceID in devices.keys where !audio.isAggregateDevice(deviceID: deviceID) {
                deviceBoosts[deviceID] = 0.0
            }
        }
        printDevices()
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
        Logger.debug(Constants.InnerMessages.selectDevice(deviceID: String(deviceID)))
    }
    
    func getSelectedDeviceVolume() -> Float? {
        guard let selectedDevice = selectedDevice else {
            return nil
        }
        
        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)
            
            for device in aggregatedDevices {
                if audio.isOutputDevice(deviceID: device) {
                    return audio.getDeviceVolume(deviceID: device).max()
                }
            }
        } else {
            return audio.getDeviceVolume(deviceID: selectedDevice).max()
        }
        
        return nil
    }
    
    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float) {
        guard let selectedDevice = selectedDevice else {
            return
        }

        let isMute = masterChannelLevel < Constants.muteVolumeLowerbound
            && leftChannelLevel < Constants.muteVolumeLowerbound
            && rightChannelLevel < Constants.muteVolumeLowerbound

        func apply(to device: AudioDeviceID) {
            let boost = deviceBoosts[device] ?? 0.0
            audio.setDeviceVolume(
                deviceID: device,
                masterChannelLevel: min(masterChannelLevel + boost, 1.0),
                leftChannelLevel: min(leftChannelLevel + boost, 1.0),
                rightChannelLevel: min(rightChannelLevel + boost, 1.0)
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
