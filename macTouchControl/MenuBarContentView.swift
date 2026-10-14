//
//  MenuBarContentView.swift
//  macTouchControl
//

import SwiftUI
import AppKit

struct MenuBarContentView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(DisplayManager.self) private var displayManager
    @Environment(TouchDeviceManager.self) private var touchManager
    @Environment(MappingStore.self) private var mappingStore
    @Environment(LocalizationManager.self) private var loc
    @Environment(TouchGestureHandler.self) private var gestureHandler

    var body: some View {
        // 運作狀態
        if permissionManager.isAllGranted {
            Text(loc.t(.menuStatusActive))
        } else {
            Text(loc.t(.menuStatusNeedPermission))
        }

        Divider()

        // 觸控設備與綁定螢幕清單
        let deviceList = Array(touchManager.devices.values)
        if deviceList.isEmpty {
            Text(loc.t(.menuNoDevices))
        } else {
            ForEach(deviceList) { device in
                let targetDisplay = mappingStore.targetDisplay(for: device.id, availableDisplays: displayManager.displays)
                let displayName = targetDisplay?.name ?? loc.t(.unassignedDisplay)
                Text("📱 \(device.name) ➔ 🖥️ \(displayName)")
            }
        }

        Divider()

        // 平板風格觸控滑動開關
        Button {
            gestureHandler.isTouchScrollEnabled.toggle()
        } label: {
            if gestureHandler.isTouchScrollEnabled {
                Text("✓ \(loc.t(.menuToggleTouchScroll))")
            } else {
                Text("   \(loc.t(.menuToggleTouchScroll))")
            }
        }

        // 長按觸發右鍵開關（Windows 風格）
        Button {
            gestureHandler.isLongPressRightClickEnabled.toggle()
        } label: {
            if gestureHandler.isLongPressRightClickEnabled {
                Text("✓ \(loc.t(.menuToggleLongPressRightClick))")
            } else {
                Text("   \(loc.t(.menuToggleLongPressRightClick))")
            }
        }

        Button(loc.t(.menuOpenPanel)) {
            openMainWindow()
        }

        Button(loc.t(.menuRescan)) {
            touchManager.rescan()
            displayManager.refreshDisplays()
        }

        Button(loc.t(.menuRevealFinder)) {
            permissionManager.revealAppInFinder()
        }

        Divider()

        // 語言選單切換
        Menu(loc.t(.menuLanguageTitle)) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    loc.selectedLanguage = lang
                } label: {
                    if loc.selectedLanguage == lang {
                        Text("✓ \(lang.displayName)")
                    } else {
                        Text("   \(lang.displayName)")
                    }
                }
            }
        }

        Divider()

        Button(loc.t(.menuQuit)) {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("macTouchControl") }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            if let window = NSApp.windows.first {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
