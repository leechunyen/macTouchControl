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

    /// 觸發切換（展開或收合）指定螢幕的 macOS 通知中心
    /// - Parameters:
    ///   - targetBounds: 觸發手勢的目標螢幕邊界（CoreGraphics 座標）。若為 nil，自動依賴游標或觸控點定位。
    ///   - returnCursorTo: 通知中心呼叫完成後游標建議還原之座標
    static func toggleNotificationCenter(
        on targetBounds: CGRect? = nil,
        returnCursorTo: CGPoint? = nil
    ) {
        let bounds = targetBounds ?? resolveDisplayBounds(for: returnCursorTo ?? NSEvent.mouseLocation)
        logger.info("[SystemGestureService] Toggling Notification Center on display bounds: \(String(describing: bounds))")

        // 觸覺回饋
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)

        // 精準合成點擊對應螢幕右上角時鐘（避開 ControlCenter 的 AX 權限限制，系統層保證相容）
        toggleViaClockClick(on: bounds, restorePoint: returnCursorTo)
    }

    /// 根據座標解析所屬螢幕的 CoreGraphics 邊界
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

    /// 精準合成點擊指定螢幕右上角的時鐘（在該螢幕展開通知中心）
    static func toggleViaClockClick(on targetBounds: CGRect, restorePoint: CGPoint? = nil) {
        // 目標螢幕右上角時鐘中心點（橫向距右緣 35pt，縱向頂部置中 12pt）
        let clockPoint = CGPoint(
            x: targetBounds.maxX - 35.0,
            y: targetBounds.minY + 12.0
        )

        logger.info("[SystemGestureService] Clicking clock on target display at (\(clockPoint.x), \(clockPoint.y))")

        let source = CGEventSource(stateID: .hidSystemState)

        // 1. 將游標移動至該螢幕時鐘位置，讓系統聚焦於該螢幕
        CGWarpMouseCursorPosition(clockPoint)

        let moveEvent = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: clockPoint,
            mouseButton: .left
        )
        moveEvent?.location = clockPoint
        moveEvent?.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
        moveEvent?.post(tap: .cghidEventTap)

        // 2. 延遲 15ms 發送 mouseDown，並在 20ms 後發送 mouseUp（確保有真實的按住時間間隔與 clickState = 1）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            guard let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: clockPoint,
                mouseButton: .left
            ) else { return }

            mouseDown.location = clockPoint
            mouseDown.setIntegerValueField(.mouseEventClickState, value: 1)
            mouseDown.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
            mouseDown.post(tap: .cghidEventTap)

            // 按住 20ms 後放開
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                guard let mouseUp = CGEvent(
                    mouseEventSource: source,
                    mouseType: .leftMouseUp,
                    mouseCursorPosition: clockPoint,
                    mouseButton: .left
                ) else { return }

                mouseUp.location = clockPoint
                mouseUp.setIntegerValueField(.mouseEventClickState, value: 1)
                mouseUp.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
                mouseUp.post(tap: .cghidEventTap)

                // 3. 若有指定還原位置，在點擊完成後無感還原
                if let restorePoint {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        CGWarpMouseCursorPosition(restorePoint)
                    }
                }
            }
        }
    }
}
