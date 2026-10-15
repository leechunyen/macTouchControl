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

    /// 純查詢方法（純函數無副作用），保證在 SwiftUI 視圖渲染期間調用不會修改狀態或觸發重繪
    func targetDisplay(for deviceID: String, availableDisplays: [DisplayInfo]) -> DisplayInfo? {
        guard let mapping = mappings[deviceID] else {
            return nil
        }

        // 1. 優先以 DisplayID 精準匹配現有螢幕
        if let exactMatch = availableDisplays.first(where: { $0.id == mapping.targetDisplayID }) {
            return exactMatch
        }

        // 2. 若螢幕重新插拔導致 DisplayID 變更，則以螢幕名稱精確匹配
        if let nameMatch = availableDisplays.first(where: { $0.name == mapping.targetDisplayName }) {
            return nameMatch
        }

        // 3. 容錯匹配：去除前後空白、忽略大小寫匹配
        let trimmedTarget = mapping.targetDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedTarget.isEmpty, let looseMatch = availableDisplays.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmedTarget
        }) {
            return looseMatch
        }

        // 4. 外接螢幕模糊匹配（非內建螢幕，名稱互相包含）
        let nonBuiltinDisplays = availableDisplays.filter { !$0.isBuiltin }
        if !trimmedTarget.isEmpty, let partialMatch = nonBuiltinDisplays.first(where: {
            let lower = $0.name.lowercased()
            return lower.contains(trimmedTarget) || trimmedTarget.contains(lower)
        }) {
            return partialMatch
        }

        return nil
    }

    /// 在螢幕硬體配置變更時（由 DisplayManager 異步觸發），調和並持久化更新螢幕插拔後變動的最新 DisplayID
    func reconcileMappings(with availableDisplays: [DisplayInfo]) {
        var didChange = false
        for (deviceID, mapping) in mappings {
            // 若 DisplayID 已精確匹配現有螢幕，無需更新
            if availableDisplays.contains(where: { $0.id == mapping.targetDisplayID }) {
                continue
            }
            // 若 DisplayID 變更但名稱相符，更新 ID
            if let matched = targetDisplay(for: deviceID, availableDisplays: availableDisplays) {
                if mapping.targetDisplayID != matched.id || mapping.targetDisplayName != matched.name {
                    mappings[deviceID]?.targetDisplayID = matched.id
                    mappings[deviceID]?.targetDisplayName = matched.name
                    didChange = true
                }
            }
        }
        if didChange {
            saveMappings()
        }
    }
}
