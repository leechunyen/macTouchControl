//
//  LocalizationManager.swift
//  macTouchControl
//

import SwiftUI
import Observation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case en_us = "en_us"
    case zh_tw = "zh_tw"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System Default"
        case .en_us:
            return "English (US)"
        case .zh_tw:
            return "繁體中文 (台灣)"
        }
    }
}

enum LocKey {
    // Header
    case appName
    case appSubtitle
    case statusActive
    case statusNeedPermission

    // Permission Section
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

    // Gestures Section
    case gesturesSectionTitle
    case nextPhaseBadge
    case comingSoonBadge
    case gestureScrollTitle
    case gestureScrollDesc
    case gestureNotificationCenterTitle
    case gestureNotificationCenterDesc
    case gestureDockTitle
    case gestureDockDesc

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
    case windowTitle
}

@Observable
@MainActor
final class LocalizationManager {
    static let shared = LocalizationManager()

    private let userDefaultsKey = "macTouchControl.appLanguage"

    var selectedLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: userDefaultsKey)
        }
    }

    var currentEffectiveLanguage: AppLanguage {
        if selectedLanguage != .system {
            return selectedLanguage
        }
        return Self.detectSystemLanguage()
    }

    init() {
        if let saved = UserDefaults.standard.string(forKey: userDefaultsKey),
           let lang = AppLanguage(rawValue: saved) {
            self.selectedLanguage = lang
        } else {
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

    private func stringForZhTW(_ key: LocKey) -> String {
        switch key {
        case .appName:
            return "macTouchControl"
        case .appSubtitle:
            return "macOS 多螢幕觸控管理與游標映射工具"
        case .statusActive:
            return "服務運作中"
        case .statusNeedPermission:
            return "需要權限"

        case .permissionSectionTitle:
            return "系統權限檢查與配置"
        case .permissionAllGranted:
            return "✓ 已具備所有必要權限"
        case .permissionMissingWarning:
            return "⚠️ 尚有權限未取得，部分功能可能無法使用"
        case .accessibilityTitle:
            return "輔助使用 (Accessibility)"
        case .accessibilityDesc:
            return "用於跨應用程式發送合成滑鼠點擊、拖曳與游標位置跳轉"
        case .inputMonitoringTitle:
            return "輸入監控 (Input Monitoring)"
        case .inputMonitoringDesc:
            return "用於在背景持續攔截並接收外部 USB / 藍牙觸控螢幕的硬體事件"
        case .permissionGrantedBadge:
            return "已授權"
        case .permissionRequestButton:
            return "取得授權"
        case .dragHelperTitle:
            return "無法授權或系統未彈出對話框？"
        case .dragHelperDesc:
            return "點擊右方按鈕會在 Finder 中直接選中此 App，您可以將它「直接拖曳」進系統設定的【輔助使用】或【輸入監控】清單中即可完成授權。"
        case .revealInFinderButton:
            return "在 Finder 中顯示 App"

        case .mappingSectionTitle:
            return "觸控面板與螢幕 1 對 1 綁定"
        case .rescanButton:
            return "重新掃描設備"
        case .mirrorModeNotice:
            return "目前螢幕設定為【鏡像模式 (Mirroring)】，所有螢幕共用相同畫面與座標空間。"
        case .noDeviceDetectedTitle:
            return "尚未偵測到外接觸控螢幕或數位板"
        case .noDeviceDetectedDesc:
            return "請連接支援 USB / 藍牙 HID 規範的觸控螢幕（如 ASUS ZenScreen、ViewSonic TD、Dell 觸控螢幕等），系統將會自動列出並供您綁定螢幕。"
        case .touchSignalActive:
            return "觸控訊號活躍中"
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
            return "已綁定: \(list)"

        case .gesturesSectionTitle:
            return "觸控手勢設定 (即將推出)"
        case .nextPhaseBadge:
            return "下階段功能"
        case .comingSoonBadge:
            return "即將推出"
        case .gestureScrollTitle:
            return "單指 / 雙指滑動滾動 (Scroll)"
        case .gestureScrollDesc:
            return "在觸控面板上拖曳時模擬滑鼠滾輪，滑動長頁面更順暢"
        case .gestureNotificationCenterTitle:
            return "右緣向內滑動開通知中心"
        case .gestureNotificationCenterDesc:
            return "從外接觸控面板的右側邊緣向內滑動，立即展開 macOS 通知中心"
        case .gestureDockTitle:
            return "底緣向內滑動顯示 Dock"
        case .gestureDockDesc:
            return "從觸控螢幕底部往上滑動，快速喚出 macOS Dock 工作列"

        case .menuStatusActive:
            return "● macTouchControl: 正常運作中"
        case .menuStatusNeedPermission:
            return "▲ macTouchControl: 尚未取得必要權限"
        case .menuNoDevices:
            return "尚未偵測到外接觸控設備"
        case .menuOpenPanel:
            return "開啟控制面板..."
        case .menuRescan:
            return "重新掃描設備"
        case .menuRevealFinder:
            return "在 Finder 中顯示 App (拖曳授權)"
        case .menuQuit:
            return "離開 macTouchControl"
        case .menuLanguageTitle:
            return "語言"

        case .defaultTouchDeviceName:
            return "觸控裝置"
        case .unassignedDisplay:
            return "未指定螢幕"
        case .windowTitle:
            return "macTouchControl 控制面板"
        }
    }

    private func stringForEnUS(_ key: LocKey) -> String {
        switch key {
        case .appName:
            return "macTouchControl"
        case .appSubtitle:
            return "macOS Multi-Monitor Touch Management & Cursor Mapping"
        case .statusActive:
            return "Service Active"
        case .statusNeedPermission:
            return "Permissions Required"

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
            return "Trouble granting permissions or no prompt appeared?"
        case .dragHelperDesc:
            return "Click the button to reveal this app in Finder, then drag and drop it into System Settings > Accessibility or Input Monitoring."
        case .revealInFinderButton:
            return "Reveal App in Finder"

        case .mappingSectionTitle:
            return "Touch Panel & Display 1-to-1 Mapping"
        case .rescanButton:
            return "Rescan Devices"
        case .mirrorModeNotice:
            return "Displays are currently in Mirroring mode, sharing the same screen and coordinate space."
        case .noDeviceDetectedTitle:
            return "No external touch screen or digitizer detected"
        case .noDeviceDetectedDesc:
            return "Please connect a USB/Bluetooth HID-compliant touch monitor (e.g. ASUS ZenScreen, ViewSonic TD, Dell touch monitors). It will automatically appear here for mapping."
        case .touchSignalActive:
            return "Touch Active"
        case .mappedDisplayLabel:
            return "Mapped Display:"
        case .testWarpButton:
            return "Test Warp Cursor"
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
            return "Mapped: \(list)"

        case .gesturesSectionTitle:
            return "Touch Gestures (Coming Soon)"
        case .nextPhaseBadge:
            return "Next Phase"
        case .comingSoonBadge:
            return "Coming Soon"
        case .gestureScrollTitle:
            return "One/Two-Finger Scrolling"
        case .gestureScrollDesc:
            return "Simulate mouse wheel scrolling when dragging on touch panel for smoother browsing."
        case .gestureNotificationCenterTitle:
            return "Swipe In from Right for Notification Center"
        case .gestureNotificationCenterDesc:
            return "Swipe inward from the right edge of the touch panel to open macOS Notification Center."
        case .gestureDockTitle:
            return "Swipe Up from Bottom to Show Dock"
        case .gestureDockDesc:
            return "Swipe inward from the bottom edge to quickly reveal the macOS Dock."

        case .menuStatusActive:
            return "● macTouchControl: Active"
        case .menuStatusNeedPermission:
            return "▲ macTouchControl: Permissions Missing"
        case .menuNoDevices:
            return "No Touch Devices Detected"
        case .menuOpenPanel:
            return "Open Control Panel..."
        case .menuRescan:
            return "Rescan Devices"
        case .menuRevealFinder:
            return "Reveal App in Finder (Drag to Authorize)"
        case .menuQuit:
            return "Quit macTouchControl"
        case .menuLanguageTitle:
            return "Language"

        case .defaultTouchDeviceName:
            return "Touch Device"
        case .unassignedDisplay:
            return "Unassigned Display"
        case .windowTitle:
            return "macTouchControl Control Panel"
        }
    }
}
