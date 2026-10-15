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
        if !isAllGranted {
            startPolling()
        }

        // 當使用者從「系統設定」授權後返回本 App 時，立即主動複查權限，無需持續輪詢
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.checkPermissions()
            if self.isAllGranted {
                self.stopPolling()
            }
        }
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
        let path = Bundle.main.bundlePath
        let url = URL(fileURLWithPath: path)

        // 1. 透過標準 NSWorkspace API 在 Finder 中選取檔案
        let selected = NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        if !selected {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        // 2. 透過系統 /usr/bin/open -R 指令作為雙重保險，確保任何環境下皆能觸發選取並開啟資料夾
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-R", path]
        try? task.run()

        // 3. 強制將 Finder 喚醒並置於最前台，確保使用者能清晰看到高亮選取的 App 檔案
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                finder.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }

    /// 開啟系統設定對應的隱私權面板
    func openSystemSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 動態輪詢權限狀態，以便使用者在系統設定勾選後 UI 能即時自動更新
    func startPolling() {
        // 若所有權限已具備，無需啟動輪詢
        if isAllGranted { return }

        pollTask?.cancel()
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self else { break }
                self.checkPermissions()
                // 一旦全部權限皆已取得，立即停止背景輪詢，杜絕 CPU 能耗浪費
                if self.isAllGranted {
                    self.stopPolling()
                    break
                }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
