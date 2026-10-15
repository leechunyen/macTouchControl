//
//  LocalizationManager.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zh_tw = "zh-Hant"
    case en_us = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .zh_tw:
            return "繁體中文 (台灣)"
        case .en_us:
            return "English (US)"
        }
    }

    /// 容錯相容解析語言字串（包含歷史格式 zh_tw、zh-TW、en_us 等）
    static func from(string: String?) -> AppLanguage? {
        guard let string = string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        let lower = string.lowercased()
        if lower == "system" {
            return .system
        }
        if lower == "en" || lower.hasPrefix("en_") || lower.hasPrefix("en-") {
            return .en_us
        }
        if lower == "zh-hant" || lower == "zh_tw" || lower == "zh-tw" || lower == "zh_hk" || lower == "zh-hk" || lower.contains("hant") || lower == "zh" {
            return .zh_tw
        }
        return AppLanguage(rawValue: string)
    }
}

enum LocKey {
    // App Header / Status
    case appSubtitle
    case statusActive
    case statusInactive

    // Permissions Section
    case permissionSectionTitle
    case permissionAllGranted
    case permissionMissingWarning
    case accessibilityTitle
    case accessibilityDesc
    case inputMonitoringTitle
    case inputMonitoringDesc
    case permissionGrantedBadge
    case permissionRequestButton
    case dragHelperTitle
    case dragHelperDesc
    case revealInFinderButton

    // Mapping Section
    case mappingSectionTitle
    case rescanButton
    case mirrorModeNotice
    case noDeviceDetectedTitle
    case noDeviceDetectedDesc
    case touchSignalActive
    case mappedDisplayLabel
    case testWarpButton
    case liveCoordinates(Int, Int)
    case panelRatio(Double, Double)

    // Displays Section
    case displaysSectionTitle(Int)
    case builtinDisplay
    case externalDisplay(UInt32)
    case mainDisplayBadge
    case mainDisplayTag
    case mirrorDisplayTag
    case resolution(Int, Int)
    case origin(Int, Int)
    case mappedDeviceList(String)
    case identifyDisplaysButton
    case identifyDisplayTooltip

    // Gestures Section
    case gesturesSectionTitle
    case gestureScrollTitle
    case gestureScrollDesc
    case naturalScrollTitle
    case naturalScrollDesc
    case scrollSensitivityTitle
    case longPressRightClickTitle
    case longPressRightClickDesc
    case longPressRightClickDisabledDesc
    case longPressDurationTitle
    case menuToggleTouchScroll
    case menuToggleLongPressRightClick
    case menuToggleRightEdgeNotificationCenter
    case gestureNotificationCenterTitle
    case gestureNotificationCenterDesc

    // MenuBar
    case menuStatusActive
    case menuStatusNeedPermission
    case menuNoDevices
    case menuOpenPanel
    case menuRescan
    case menuRevealFinder
    case menuQuit
    case menuLanguageTitle

    // Device defaults
    case defaultTouchDeviceName
    case unassignedDisplay
    case disconnectedDisplay
    case windowTitle

    // Auto Start / Settings
    case autoStartTitle
    case autoStartDesc
    case menuToggleAutoStart
}

@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private let userDefaultsKey = "macTouchControl.appLanguage"
    private let legacyKey = "macTouchControl.language"
    private let defaults: UserDefaults

    var selectedLanguage: AppLanguage {
        didSet {
            defaults.set(selectedLanguage.rawValue, forKey: userDefaultsKey)
            defaults.set(selectedLanguage.rawValue, forKey: legacyKey)
            defaults.synchronize()
        }
    }

    var currentEffectiveLanguage: AppLanguage {
        if selectedLanguage != .system {
            return selectedLanguage
        }
        return Self.detectSystemLanguage()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.string(forKey: userDefaultsKey) ?? defaults.string(forKey: legacyKey)
        if let lang = AppLanguage.from(string: saved) {
            self.selectedLanguage = lang
        } else {
            // 預設語言為 System (跟隨系統)
            self.selectedLanguage = .system
        }
    }

    /// 先抓系統語言偏好，非 zh_tw 相關者一律 fallback 至 en_us
    nonisolated static func detectSystemLanguage() -> AppLanguage {
        resolveLanguage(from: Locale.preferredLanguages)
    }

    /// 根據語系優先清單解析，若無符合 zh_tw 者一律 fallback 至 en_us
    nonisolated static func resolveLanguage(from preferredLanguages: [String]) -> AppLanguage {
        for lang in preferredLanguages {
            let lower = lang.lowercased()
            // 匹配繁體中文（台灣、香港、澳門或標準 zh-Hant）
            if lower.hasPrefix("zh-tw") ||
               lower.hasPrefix("zh-hant") ||
               lower.contains("zh-hant-tw") ||
               lower.contains("zh-hk") {
                return .zh_tw
            }
            if lower.hasPrefix("en") {
                return .en_us
            }
        }
        // 未匹配或系統為其他語言時（例如日文、法文、德文等），一律 fallback 去 en_us
        return .en_us
    }

    func t(_ key: LocKey) -> String {
        switch currentEffectiveLanguage {
        case .zh_tw:
            return stringForZhTW(key)
        case .en_us, .system:
            return stringForEnUS(key)
        }
    }

    // MARK: - 繁體中文（台灣標準資訊科技用語：裝置、螢幕、捲動、預設）
    private func stringForZhTW(_ key: LocKey) -> String {
        switch key {
        case .appSubtitle:
            return "觸控螢幕工具"
        case .statusActive:
            return "服務運作中"
        case .statusInactive:
            return "服務暫停（缺少必要權限）"

        case .permissionSectionTitle:
            return "系統安全性與權限設定"
        case .permissionAllGranted:
            return "✓ 所有必要權限皆已授權完畢"
        case .permissionMissingWarning:
            return "⚠️ 尚未授予完整權限，部分功能可能無法正常運作。"
        case .accessibilityTitle:
            return "輔助使用 (Accessibility)"
        case .accessibilityDesc:
            return "用於發送跨視窗的合成滑鼠點擊、拖曳、捲動與跨螢幕游標定位跳轉。"
        case .inputMonitoringTitle:
            return "輸入監控 (Input Monitoring)"
        case .inputMonitoringDesc:
            return "用於背景接收外接 USB / 藍牙觸控螢幕的硬體原始觸控報告與座標。"
        case .permissionGrantedBadge:
            return "已授權"
        case .permissionRequestButton:
            return "前往授權"
        case .dragHelperTitle:
            return "無法點選授權或未跳出對話框？"
        case .dragHelperDesc:
            return "點選右側按鈕在 Finder 中開啟此 App，將 App 圖示直接拖曳至系統設定的「輔助使用」或「輸入監控」清單中即可快速完成授權。"
        case .revealInFinderButton:
            return "在 Finder 中顯示 App"

        case .mappingSectionTitle:
            return "觸控面板與螢幕 1 對 1 綁定"
        case .rescanButton:
            return "重新掃描裝置"
        case .mirrorModeNotice:
            return "目前螢幕設定為【鏡像模式 (Mirroring)】，所有螢幕共用相同畫面與座標空間。"
        case .noDeviceDetectedTitle:
            return "尚未偵測到外接觸控螢幕或數位板"
        case .noDeviceDetectedDesc:
            return "請連接支援 USB / 藍牙 HID 規範的觸控螢幕（如 ASUS ZenScreen、ViewSonic TD、Dell 觸控螢幕等），系統將會自動列出並供您綁定螢幕。"
        case .touchSignalActive:
            return "觸控訊號作用中"
        case .mappedDisplayLabel:
            return "對應綁定的顯示器："
        case .testWarpButton:
            return "測試游標跳至此螢幕"
        case .liveCoordinates(let x, let y):
            return "即時游標座標: X: \(x), Y: \(y)"
        case .panelRatio(let x, let y):
            return "面板比例: X: \(String(format: "%.2f", x)), Y: \(String(format: "%.2f", y))"

        case .displaysSectionTitle(let count):
            return "目前偵測到的顯示器 (\(count) 個)"
        case .builtinDisplay:
            return "內建螢幕"
        case .externalDisplay(let id):
            return "外接螢幕 \(id)"
        case .mainDisplayBadge:
            return "主螢幕"
        case .mainDisplayTag:
            return " [主螢幕]"
        case .mirrorDisplayTag:
            return " [鏡像]"
        case .resolution(let w, let h):
            return "解析度: \(w) × \(h)"
        case .origin(let x, let y):
            return "原點: (\(x), \(y))"
        case .mappedDeviceList(let list):
            return "已綁定裝置: \(list)"
        case .identifyDisplaysButton:
            return "識別螢幕"
        case .identifyDisplayTooltip:
            return "在實體螢幕上顯示識別號碼與名稱"

        case .gesturesSectionTitle:
            return "觸控手勢與捲動體驗 (Touch Gestures)"
        case .gestureScrollTitle:
            return "觸控螢幕雙向捲動 (平板 / 手機模式)"
        case .gestureScrollDesc:
            return "如同平板直接在螢幕上滑動捲動網頁與視窗內容，完整支援上下與水平橫向捲動、慣性滑行與防誤觸輕點"
        case .naturalScrollTitle:
            return "自然捲動方向 (Natural Scrolling)"
        case .naturalScrollDesc:
            return "畫面內容直接跟隨手指滑動方向位移（預設開啟）"
        case .scrollSensitivityTitle:
            return "捲動靈敏度"
        case .longPressRightClickTitle:
            return "長按右鍵 (Windows / iPad 風格)"
        case .longPressRightClickDesc:
            return "開啟時：定點按住顯示倒數光圈，光圈內放開為右鍵；光圈跑完不放開為 Click Hold 直到放開"
        case .longPressRightClickDisabledDesc:
            return "關閉時：停用右鍵與倒數光圈，按住直接為 Click Hold 直到放開（一般拖曳與點擊完全不受影響）"
        case .longPressDurationTitle:
            return "長按倒數時間"
        case .menuToggleTouchScroll:
            return "觸控螢幕滑動捲動模式"
        case .menuToggleLongPressRightClick:
            return "長按右鍵"
        case .menuToggleRightEdgeNotificationCenter:
            return "右緣向內滑開通知中心"
        case .gestureNotificationCenterTitle:
            return "右緣向內滑動開通知中心"
        case .gestureNotificationCenterDesc:
            return "從外接觸控面板的右側邊緣向內滑動，立即展開 macOS 通知中心"

        case .menuStatusActive:
            return "● macTouchControl: 服務運作中"
        case .menuStatusNeedPermission:
            return "▲ macTouchControl: 尚未取得必要權限"
        case .menuNoDevices:
            return "尚未偵測到外接觸控裝置"
        case .menuOpenPanel:
            return "開啟控制面板..."
        case .menuRescan:
            return "重新掃描裝置"
        case .menuRevealFinder:
            return "在 Finder 中顯示 App (拖曳授權)"
        case .menuQuit:
            return "結束 macTouchControl"
        case .menuLanguageTitle:
            return "語言 (Language)"

        case .defaultTouchDeviceName:
            return "觸控裝置"
        case .unassignedDisplay:
            return "未指定螢幕"
        case .disconnectedDisplay:
            return "已中斷連線"
        case .windowTitle:
            return "macTouchControl - 觸控螢幕工具"

        case .autoStartTitle:
            return "開機時自動啟動"
        case .autoStartDesc:
            return "登入時自動在選單列常駐運行，不自動彈出控制面板"
        case .menuToggleAutoStart:
            return "開機時自動啟動 (Auto Start)"
        }
    }

    // MARK: - English (US)
    private func stringForEnUS(_ key: LocKey) -> String {
        switch key {
        case .appSubtitle:
            return "Touchscreen Utility"
        case .statusActive:
            return "Service Active"
        case .statusInactive:
            return "Service Paused (Missing Permissions)"

        case .permissionSectionTitle:
            return "System Permissions"
        case .permissionAllGranted:
            return "✓ All necessary permissions granted"
        case .permissionMissingWarning:
            return "⚠️ Permissions missing. Some features may not work."
        case .accessibilityTitle:
            return "Accessibility"
        case .accessibilityDesc:
            return "Required for sending synthetic mouse clicks, dragging, and cursor warping across apps."
        case .inputMonitoringTitle:
            return "Input Monitoring"
        case .inputMonitoringDesc:
            return "Required for receiving hardware events from external USB/Bluetooth touch monitors in the background."
        case .permissionGrantedBadge:
            return "Granted"
        case .permissionRequestButton:
            return "Grant Access"
        case .dragHelperTitle:
            return "Cannot grant or dialog didn't show?"
        case .dragHelperDesc:
            return "Click the button on the right to reveal this App in Finder. You can directly drag it into the Accessibility or Input Monitoring list in System Settings to complete authorization."
        case .revealInFinderButton:
            return "Reveal in Finder"

        case .mappingSectionTitle:
            return "Touch Panel & Display 1-to-1 Mapping"
        case .rescanButton:
            return "Rescan Devices"
        case .mirrorModeNotice:
            return "Currently in Mirroring Mode. All displays share the same desktop and coordinate space."
        case .noDeviceDetectedTitle:
            return "No External Touch Monitors Detected"
        case .noDeviceDetectedDesc:
            return "Please connect an external touch monitor supporting standard USB/Bluetooth HID (e.g. ASUS ZenScreen, ViewSonic TD, Dell Touch). It will automatically appear here."
        case .touchSignalActive:
            return "Touch Signal Active"
        case .mappedDisplayLabel:
            return "Mapped Display:"
        case .testWarpButton:
            return "Test Warp"
        case .liveCoordinates(let x, let y):
            return "Live Cursor: X: \(x), Y: \(y)"
        case .panelRatio(let x, let y):
            return "Panel Ratio: X: \(String(format: "%.2f", x)), Y: \(String(format: "%.2f", y))"

        case .displaysSectionTitle(let count):
            return "Detected Displays (\(count))"
        case .builtinDisplay:
            return "Built-in Display"
        case .externalDisplay(let id):
            return "External Display \(id)"
        case .mainDisplayBadge:
            return "Main"
        case .mainDisplayTag:
            return " [Main]"
        case .mirrorDisplayTag:
            return " [Mirror]"
        case .resolution(let w, let h):
            return "Resolution: \(w) × \(h)"
        case .origin(let x, let y):
            return "Origin: (\(x), \(y))"
        case .mappedDeviceList(let list):
            return "Mapped Devices: \(list)"
        case .identifyDisplaysButton:
            return "Identify"
        case .identifyDisplayTooltip:
            return "Show identification badge on screen"

        case .gesturesSectionTitle:
            return "Touch Gestures & Scrolling"
        case .gestureScrollTitle:
            return "Touchscreen 2D Scrolling (Tablet Mode)"
        case .gestureScrollDesc:
            return "Direct touchscreen scrolling like a tablet, supporting both vertical and horizontal directions, natural scroll, momentum fling, and tap anti-misclick"
        case .naturalScrollTitle:
            return "Natural Scroll Direction"
        case .naturalScrollDesc:
            return "Content moves in the exact direction your finger slides (Enabled by default)"
        case .scrollSensitivityTitle:
            return "Scroll Sensitivity"
        case .longPressRightClickTitle:
            return "Long Press Right-Click (Windows / iPad Style)"
        case .longPressRightClickDesc:
            return "When enabled: hold to show countdown ring, release during countdown for Right-Click; hold past countdown for Click Hold"
        case .longPressRightClickDisabledDesc:
            return "When disabled: Right-Click & ring disabled, holding acts directly as Click Hold (dragging and tapping unaffected)"
        case .longPressDurationTitle:
            return "Long-Press Duration"
        case .menuToggleTouchScroll:
            return "Tablet Touch Scrolling"
        case .menuToggleLongPressRightClick:
            return "Long Press Right-Click"
        case .menuToggleRightEdgeNotificationCenter:
            return "Swipe Right Edge for Notification Center"
        case .gestureNotificationCenterTitle:
            return "Swipe In from Right for Notification Center"
        case .gestureNotificationCenterDesc:
            return "Swipe inward from the right edge of the touch monitor to open Notification Center."

        case .menuStatusActive:
            return "● macTouchControl: Active"
        case .menuStatusNeedPermission:
            return "▲ macTouchControl: Permissions Needed"
        case .menuNoDevices:
            return "No External Touch Devices Detected"
        case .menuOpenPanel:
            return "Open Preferences..."
        case .menuRescan:
            return "Rescan Devices"
        case .menuRevealFinder:
            return "Reveal in Finder (Drag to Authorize)"
        case .menuQuit:
            return "Quit macTouchControl"
        case .menuLanguageTitle:
            return "Language"

        case .defaultTouchDeviceName:
            return "Touch Device"
        case .unassignedDisplay:
            return "Unassigned Display"
        case .disconnectedDisplay:
            return "Disconnected"
        case .windowTitle:
            return "macTouchControl - Touchscreen Utility"

        case .autoStartTitle:
            return "Launch at Login"
        case .autoStartDesc:
            return "Automatically start in menu bar upon login without opening the control panel"
        case .menuToggleAutoStart:
            return "Launch at Login (Auto Start)"
        }
    }
}
