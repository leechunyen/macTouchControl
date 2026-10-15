//
//  SystemGestureService.swift
//  macTouchControl
//

import AppKit
import ApplicationServices
import OSLog

@MainActor
enum SystemGestureService {
    private static let logger = Logger(subsystem: "com.apple-cylee.macTouchControl", category: "SystemGesture")

    /// 取得目前滑鼠游標在 CoreGraphics 座標系下的位置（AppKit 座標轉換至 CG 座標）
    static var currentCursorPointInCG: CGPoint {
        let mouseLoc = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        return CGPoint(x: mouseLoc.x, y: primaryHeight - mouseLoc.y)
    }

    /// 觸發切換（展開或收合）指定螢幕的 macOS 通知中心
    /// - Parameters:
    ///   - targetBounds: 觸發手勢的目標螢幕邊界（CoreGraphics 座標）。若為 nil，自動依賴游標或觸控點定位。
    ///   - returnCursorTo: 通知中心呼叫完成後游標建議還原之座標（CoreGraphics 座標）
    static func toggleNotificationCenter(
        on targetBounds: CGRect? = nil,
        returnCursorTo: CGPoint? = nil
    ) {
        let cgCursor = returnCursorTo ?? currentCursorPointInCG
        let bounds = targetBounds ?? resolveDisplayBounds(for: cgCursor)
        logger.info("[SystemGestureService] Toggling Notification Center on display bounds: \(String(describing: bounds))")

        // 觸覺回饋
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        // 1. 優先嘗試透過 Accessibility API 精準尋找時鐘控制項或觸發 AXPressAction
        if triggerClockViaAccessibility(on: bounds, restorePoint: returnCursorTo) {
            return
        }

        // 2. 備援方案：若 AX 查無控制項（例如全螢幕、選單列自動隱藏或限制），使用幾何邊界精準合成點擊
        toggleViaClockClick(on: bounds, restorePoint: returnCursorTo)
    }

    /// 根據 CoreGraphics 座標解析所屬螢幕的邊界（支援多螢幕負座標與任意排列配置）
    static func resolveDisplayBounds(for point: CGPoint) -> CGRect {
        for screen in NSScreen.screens {
            guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                continue
            }
            let bounds = CGDisplayBounds(screenNumber)
            if bounds.contains(point) {
                return bounds
            }
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    /// 透過 Accessibility API 查找目標螢幕上的時鐘控制項
    private static func triggerClockViaAccessibility(on targetBounds: CGRect, restorePoint: CGPoint?) -> Bool {
        guard PermissionManager.shared.isAccessibilityGranted else { return false }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first else {
            return false
        }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuBarValue: AnyObject?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBarValue) == .success,
              let menuBar = menuBarValue else {
            return false
        }

        var childrenValue: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return false
        }

        for item in children.reversed() {
            var posValue: AnyObject?
            var sizeValue: AnyObject?
            if AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posValue) == .success,
               AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success {
                var pos = CGPoint.zero
                var size = CGSize.zero
                AXValueGetValue(posValue as! AXValue, .cgPoint, &pos)
                AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

                let itemRect = CGRect(origin: pos, size: size)
                if targetBounds.contains(CGPoint(x: itemRect.midX, y: itemRect.midY)) ||
                   (abs(itemRect.maxX - targetBounds.maxX) < 200 && abs(itemRect.minY - targetBounds.minY) < 50) {
                    if AXUIElementPerformAction(item, kAXPressAction as CFString) == .success {
                        logger.info("[SystemGestureService] Successfully triggered Notification Center via AXPressAction")
                        return true
                    }
                    let center = CGPoint(x: itemRect.midX, y: itemRect.midY)
                    clickAtPoint(center, restorePoint: restorePoint)
                    return true
                }
            }
        }
        return false
    }

    /// 精準合成點擊指定螢幕右上角的時鐘（在該螢幕展開通知中心）
    static func toggleViaClockClick(on targetBounds: CGRect, restorePoint: CGPoint? = nil) {
        let clockPoint = CGPoint(
            x: targetBounds.maxX - 35.0,
            y: targetBounds.minY + 12.0
        )
        clickAtPoint(clockPoint, restorePoint: restorePoint)
    }

    private static func clickAtPoint(_ point: CGPoint, restorePoint: CGPoint?) {
        logger.info("[SystemGestureService] Clicking clock at (\(point.x), \(point.y))")
        let source = CGEventSource(stateID: .hidSystemState)

        CGWarpMouseCursorPosition(point)

        let moveEvent = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        moveEvent?.location = point
        moveEvent?.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
        moveEvent?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            guard let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: point,
                mouseButton: .left
            ) else { return }

            mouseDown.location = point
            mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseDown.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
            mouseDown.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let mouseUp = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: point,
                    mouseButton: .left
                ) else { return }

                mouseUp.location = point
                mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
                mouseUp.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
                mouseUp.post(tap: .cghidEventTap)

                if let restorePoint {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        CGWarpMouseCursorPosition(restorePoint)
                    }
                }
            }
        }
    }
}
