//
//  AutoStartManager.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import Foundation
import ServiceManagement
import AppKit
import SwiftUI

// MARK: - Auto Start & Login Item Manager

/// 開機自動啟動管理器（Auto Start / Launch at Login）
/// 1. 預設為關閉，由使用者自主決定是否啟用
/// 2. 每次 App 啟動或生命週期切換時，向 macOS 系統 (SMAppService) 查詢最新狀態
/// 3. 精確判定本次 App 是否由 Auto Start 開機自動引導啟動
@Observable
@MainActor
final class AutoStartManager {
    static let shared = AutoStartManager()

    /// 系統當前是否已啟用登入時自動啟動 (Launch at Login)
    var isAutoStartEnabled: Bool = false

    /// 記錄本次 App 啟動是否由 Auto Start (Login Item) 自動引導帶起
    private(set) var launchedAsLoginItem: Bool = false

    init() {
        checkStatus()
    }

    /// 每次 App 啟動時向系統 SMAppService 查詢真實啟用狀態
    func checkStatus() {
        if #available(macOS 13.0, *) {
            let status = SMAppService.mainApp.status
            self.isAutoStartEnabled = (status == .enabled)
        } else {
            self.isAutoStartEnabled = false
        }
    }

    /// 設定或切換自動啟動狀態
    func setAutoStart(enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("Failed to update auto start: \(error.localizedDescription)")
            }
            checkStatus()
        }
    }

    /// 檢查本次啟動是否是由 macOS 登入項目（Auto Start）觸發
    func evaluateLaunchTrigger() {
        if let event = NSAppleEventManager.shared().currentAppleEvent {
            let keyAELaunchedAsLogInItem = AEKeyword(0x6c676974) // "lgit"
            let isLoginItem = (event.eventID == kAEOpenApplication &&
                               event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem)
            self.launchedAsLoginItem = isLoginItem
        }
    }
}

// MARK: - App Delegate & Window Lifecycle Management

/// 掌管主視窗生命週期、Dock 圖示動態顯隱與開機靜默啟動行為
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let shared = AppDelegate()

    weak var mainWindow: NSWindow?
    private var isFirstLaunchCheck = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        AutoStartManager.shared.evaluateLaunchTrigger()
        AutoStartManager.shared.checkStatus()

        // 監聽所有視窗焦點變化
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    func registerMainWindow(_ window: NSWindow) {
        self.mainWindow = window
        window.delegate = self

        if AutoStartManager.shared.launchedAsLoginItem && isFirstLaunchCheck {
            isFirstLaunchCheck = false
            // 若為開機 Auto Start 自動啟動：
            // 隱藏控制面板視窗、隱藏 Dock 圖標，僅在 Menu Bar 常駐！
            window.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
        } else {
            // 使用者手動雙擊啟動：
            // 正常呈現控制面板視窗與 Dock 圖標
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // 當使用者點擊視窗左上角紅叉叉關閉控制面板時
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // 控制面板沒開時，Dock 不顯示圖標，僅保留選單列（Menu Bar）運行
        sender.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === mainWindow else { return }
        if window.isVisible {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// 從 Menu Bar 點選「打開控制面板」時調用
    func openControlPanel() {
        // 控制面板開啟時，還原為 .regular 模式，Dock 圖標即時出現
        NSApp.setActivationPolicy(.regular)
        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                registerMainWindow(window)
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}

// MARK: - Window Accessor for SwiftUI

/// 輔助 SwiftUI 視窗捕獲原生 NSWindow 實例以綁定 Delegate
struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                callback(window)
            }
        }
    }
}
