//
//  MappingStore.swift
//  macTouchControl
//

import SwiftUI
import CoreGraphics
import Observation

struct TouchDeviceMapping: Codable, Identifiable {
    var id: String { touchDeviceID }
    let touchDeviceID: String
    let touchDeviceName: String
    var targetDisplayID: UInt32
    var targetDisplayName: String
}

@Observable
@MainActor
final class MappingStore {
    static let shared = MappingStore()

    private let defaultsKey = "macTouchControl.mappings"

    var mappings: [String: TouchDeviceMapping] = [:]

    init() {
        loadMappings()
    }

    func loadMappings() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([String: TouchDeviceMapping].self, from: data) {
            // 自動清理過去儲存的 Apple 內建鍵盤／觸控板紀錄
            self.mappings = decoded.filter { _, mapping in
                let lower = mapping.touchDeviceName.lowercased()
                return !lower.contains("apple internal") &&
                       !lower.contains("trackpad") &&
                       !lower.contains("internal keyboard")
            }
        }
    }

    func saveMappings() {
        if let encoded = try? JSONEncoder().encode(mappings) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
            UserDefaults.standard.synchronize()
        }
    }

    func bind(deviceID: String, deviceName: String, display: DisplayInfo) {
        let mapping = TouchDeviceMapping(
            touchDeviceID: deviceID,
            touchDeviceName: deviceName,
            targetDisplayID: display.id,
            targetDisplayName: display.name
        )
        mappings[deviceID] = mapping
        saveMappings()
    }

    func unbind(deviceID: String) {
        mappings.removeValue(forKey: deviceID)
        saveMappings()
    }

    func targetDisplay(for deviceID: String, availableDisplays: [DisplayInfo]) -> DisplayInfo? {
        guard let mapping = mappings[deviceID] else {
            return nil
        }

        // 1. 優先以 DisplayID 精準匹配現有螢幕
        if let exactMatch = availableDisplays.first(where: { $0.id == mapping.targetDisplayID }) {
            return exactMatch
        }

        // 2. 若螢幕重新插拔導致 DisplayID 變更，則以螢幕名稱模糊匹配
        if let nameMatch = availableDisplays.first(where: { $0.name == mapping.targetDisplayName }) {
            // 同步更新最新 DisplayID
            mappings[deviceID]?.targetDisplayID = nameMatch.id
            saveMappings()
            return nameMatch
        }

        return nil
    }
}
