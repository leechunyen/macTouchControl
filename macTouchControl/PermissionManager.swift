//
//  PermissionManager.swift
//  macTouchControl
//

import SwiftUI
import AppKit
import ApplicationServices
import CoreGraphics
import Observation

@Observable
@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    var isAccessibilityGranted: Bool = false
    var isInputMonitoringGranted: Bool = false
    var hasCheckedInitially: Bool = false

    private var pollTask: Task<Void, Never>?

    var isAllGranted: Bool {
        isAccessibilityGranted && isInputMonitoringGranted
    }

    init() {
        checkPermissions()
        startPolling()
    }

    func checkPermissions() {
        // 1. Accessibility (輔助使用權限，用於 CGEvent 發送與游標控制)
        let axTrusted = AXIsProcessTrusted()
        self.isAccessibilityGranted = axTrusted

        // 2. Input Monitoring (輸入監控權限，用於背景讀取 IOHIDManager 設備事件)
        let inputMonitoringTrusted = CGPreflightListenEventAccess()
        self.isInputMonitoringGranted = inputMonitoringTrusted

        self.hasCheckedInitially = true
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        self.isAccessibilityGranted = trusted

        if !trusted {
            openSystemSettings(pane: "Privacy_Accessibility")
        }
    }

    func requestInputMonitoring() {
        let granted = CGRequestListenEventAccess()
        self.isInputMonitoringGranted = granted

        if !granted {
            openSystemSettings(pane: "Privacy_ListenEvent")
        }
    }

    func requestAllPermissions() {
        requestAccessibility()
        requestInputMonitoring()
    }

    /// 在 Finder 中顯示當前 App 執行檔/應用程式本體，方便使用者拖曳進隱私設定列表
    func revealAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// 開啟系統設定對應的隱私權面板
    func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 動態輪詢權限狀態，以便使用者在系統設定勾選後 UI 能即時自動更新
    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { break }
                self.checkPermissions()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
