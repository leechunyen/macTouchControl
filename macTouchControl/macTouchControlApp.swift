//
//  macTouchControlApp.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import SwiftUI
import AppKit

@main
struct macTouchControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var permissionManager = PermissionManager.shared
    @State private var displayManager = DisplayManager.shared
    @State private var touchManager = TouchDeviceManager.shared
    @State private var mappingStore = MappingStore.shared
    @State private var localizationManager = LocalizationManager.shared
    @State private var gestureHandler = TouchGestureHandler.shared
    @State private var autoStartManager = AutoStartManager.shared

    init() {
        // App 啟動時先檢查是否具備所有需要的權限並檢查開機啟動狀態
        PermissionManager.shared.checkPermissions()
        AutoStartManager.shared.checkStatus()
    }

    var body: some Scene {
        Window(localizationManager.t(.windowTitle), id: "main-window") {
            ContentView()
                .environment(permissionManager)
                .environment(displayManager)
                .environment(touchManager)
                .environment(mappingStore)
                .environment(localizationManager)
                .environment(gestureHandler)
                .environment(autoStartManager)
                .onAppear {
                    // 若非開機靜默啟動且缺少權限，確保面板浮至最前方方便使用者授權
                    if !permissionManager.isAllGranted && !autoStartManager.launchedAsLoginItem {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra("macTouchControl", systemImage: permissionManager.isAllGranted ? "hand.tap" : "hand.tap.fill") {
            MenuBarContentView()
                .environment(permissionManager)
                .environment(displayManager)
                .environment(touchManager)
                .environment(mappingStore)
                .environment(localizationManager)
                .environment(gestureHandler)
                .environment(autoStartManager)
        }
    }
}
