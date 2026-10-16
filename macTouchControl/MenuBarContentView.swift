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
    @Environment(AutoStartManager.self) private var autoStartManager

    var body: some View {
        // 狀態摘要
        if permissionManager.isAllGranted {
            Text(loc.t(.menuStatusActive))
        } else {
            Text(loc.t(.menuStatusNeedPermission))
        }

        Divider()

        // 裝置清單與綁定
        let deviceList = Array(touchManager.devices.values)
        if deviceList.isEmpty {
            Text(loc.t(.menuNoDevices))
        } else {
            ForEach(deviceList) { device in
                let target = mappingStore.targetDisplay(for: device.id, availableDisplays: displayManager.displays)
                Text("• \(device.name) → \(target?.name ?? loc.t(.unassignedDisplay))")
            }
        }

        Divider()

        // 觸控捲動開關
        Button {
            gestureHandler.isTouchScrollEnabled.toggle()
        } label: {
            if gestureHandler.isTouchScrollEnabled {
                Text("✓ \(loc.t(.menuToggleTouchScroll))")
            } else {
                Text("   \(loc.t(.menuToggleTouchScroll))")
            }
        }

        // 長按右鍵開關
        Button {
            gestureHandler.isLongPressRightClickEnabled.toggle()
        } label: {
            if gestureHandler.isLongPressRightClickEnabled {
                Text("✓ \(loc.t(.menuToggleLongPressRightClick))")
            } else {
                Text("   \(loc.t(.menuToggleLongPressRightClick))")
            }
        }

        // 右側邊緣向內滑開通知中心開關
        Button {
            gestureHandler.isRightEdgeNotificationCenterEnabled.toggle()
        } label: {
            if gestureHandler.isRightEdgeNotificationCenterEnabled {
                Text("✓ \(loc.t(.menuToggleRightEdgeNotificationCenter))")
            } else {
                Text("   \(loc.t(.menuToggleRightEdgeNotificationCenter))")
            }
        }

        // 開機自動啟動開關 (Auto Start)
        Button {
            autoStartManager.setAutoStart(enabled: !autoStartManager.isAutoStartEnabled)
        } label: {
            if autoStartManager.isAutoStartEnabled {
                Text("✓ \(loc.t(.menuToggleAutoStart))")
            } else {
                Text("   \(loc.t(.menuToggleAutoStart))")
            }
        }

        Button(loc.t(.menuOpenPanel)) {
            openMainWindow()
        }

        Button(loc.t(.menuRescan)) {
            touchManager.rescan()
            displayManager.refreshDisplays()
        }

        Button(loc.t(.identifyDisplaysButton)) {
            DisplayIdentifier.shared.identifyAllDisplays()
        }

        Button(loc.t(.menuRevealFinder)) {
            permissionManager.revealAppInFinder()
        }

        Divider()

        // 贊助作者 (Buy Me a Coffee)
        Button("☕️ \(loc.t(.buyMeACoffee))") {
            if let url = URL(string: "https://buymeacoffee.com/cylee99") {
                NSWorkspace.shared.open(url)
            }
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
        AppDelegate.shared.openControlPanel()
    }
}
