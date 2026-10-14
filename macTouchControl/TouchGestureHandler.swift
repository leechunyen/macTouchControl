//
//  TouchGestureHandler.swift
//  macTouchControl
//

import Foundation
import AppKit
import CoreGraphics
import Observation

enum TouchPhase {
    case began
    case moved
    case ended
    case cancelled
}

struct TouchSample {
    let point: CGPoint          // Target screen coordinate
    let normalized: CGPoint     // (0...1, 0...1) within the touch screen
    let timestamp: TimeInterval
    let phase: TouchPhase
}

/// 負責處理外接觸控螢幕之滑動手勢、輕點點擊、Windows 風格長按右鍵與 2D 慣性捲動
@Observable
@MainActor
final class TouchGestureHandler {
    static let shared = TouchGestureHandler()

    // MARK: - User Settings (預設均為開啟)

    /// 是否啟用手機／平板風格的觸控螢幕滑動體驗（預設開啟）
    var isTouchScrollEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTouchScrollEnabled, forKey: "macTouchControl.touchScrollEnabled")
        }
    }

    /// 自然滑動方向：內容直接跟隨手指移動方向捲動（預設開啟）
    var naturalScroll: Bool = true {
        didSet {
            UserDefaults.standard.set(naturalScroll, forKey: "macTouchControl.naturalScroll")
        }
    }

    /// 滑動靈敏度
    var scrollSensitivity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "macTouchControl.scrollSensitivity")
        }
    }

    // MARK: - Internal Gesture State

    private enum GestureState {
        case idle
        /// 手指剛落下，尚未判定為點擊、滑動或長按
        case pending(startPoint: CGPoint, startNormalized: CGPoint, startTime: TimeInterval, maxDisplacement: CGFloat)
        /// 正在進行雙向（垂直與水平）滑動捲動
        case scrolling(lastPoint: CGPoint, velocityTracker: [(TimeInterval, CGPoint)])
        /// 長按時間已達標並觸發右鍵
        case longPressTriggered(point: CGPoint)
    }

    private var gestureState: GestureState = .idle
    private var longPressTimer: Timer?

    // MARK: - Precision Thresholds (防誤觸與零延遲跟手參數)

    /// 滑動識別閥值：手指移動超過 4.0 點即判定為滑動，反應即時無延遲感
    private let slopThreshold: CGFloat = 4.0

    /// 長按右鍵閥值：長按 0.45 秒觸發右鍵（如同 Windows / Surface 觸控體驗）
    private let longPressThreshold: TimeInterval = 0.45

    /// 有效輕點最短時間 (35ms)，過濾硬體電容抖動造成的幽靈誤點擊
    private let minTapDuration: TimeInterval = 0.035

    /// 有效輕點最長時間 (320ms)，超過此時間未滑動亦不判定為誤點擊
    private let maxTapDuration: TimeInterval = 0.32

    /// 慣性摩擦衰減係數
    private let friction: Double = 0.94

    /// 觸發慣性捲動的最低釋放速度 (px/s)
    private let minMomentumVelocity: Double = 60.0

    /// 慣性停止速度 (px/s)
    private let stopMomentumVelocity: Double = 6.0

    // 慣性滑動計時與速度向量
    private var momentumTimer: Timer?
    private var momentumVx: Double = 0
    private var momentumVy: Double = 0

    // 次像素累加器（垂直與水平）
    private var fractionalRemainderX: CGFloat = 0
    private var fractionalRemainderY: CGFloat = 0

    init() {
        // 註冊系統預設值：滑動模式與自然捲動預設必須開啟
        UserDefaults.standard.register(defaults: [
            "macTouchControl.touchScrollEnabled": true,
            "macTouchControl.naturalScroll": true,
            "macTouchControl.scrollSensitivity": 1.0
        ])

        self.isTouchScrollEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.touchScrollEnabled")
        self.naturalScroll = UserDefaults.standard.bool(forKey: "macTouchControl.naturalScroll")

        let savedSensitivity = UserDefaults.standard.double(forKey: "macTouchControl.scrollSensitivity")
        self.scrollSensitivity = savedSensitivity > 0 ? savedSensitivity : 1.0
    }

    // MARK: - Touch Dispatch Entry Point

    func handleTouch(
        point: CGPoint,
        normalized: CGPoint,
        isDown: Bool,
        tipChanged: Bool
    ) {
        let now = ProcessInfo.processInfo.systemUptime

        if tipChanged {
            if isDown {
                handleTouchDown(point: point, normalized: normalized, timestamp: now)
            } else {
                handleTouchUp(point: point, timestamp: now)
            }
        } else if isDown {
            handleTouchMoved(point: point, timestamp: now)
        }
    }

    // MARK: - Private Gesture Handlers

    private func handleTouchDown(point: CGPoint, normalized: CGPoint, timestamp: TimeInterval) {
        // 一碰即停：立即中斷進行中的慣性捲動
        stopMomentum()

        cancelLongPressTimer()
        fractionalRemainderX = 0
        fractionalRemainderY = 0

        guard isTouchScrollEnabled else {
            // 若關閉平板滑動模式，走傳統直接滑鼠拖曳
            synthesizeMouseEvent(type: .leftMouseDown, point: point)
            return
        }

        gestureState = .pending(
            startPoint: point,
            startNormalized: normalized,
            startTime: timestamp,
            maxDisplacement: 0
        )

        // Windows 觸控風格：長按定點約 0.45 秒觸發右鍵選單
        let timer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .pending(let startPoint, _, _, let maxDisp) = self.gestureState {
                if maxDisp < self.slopThreshold {
                    self.gestureState = .longPressTriggered(point: startPoint)
                    self.synthesizeRightClick(at: startPoint)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.longPressTimer = timer
    }

    private func handleTouchMoved(point: CGPoint, timestamp: TimeInterval) {
        guard isTouchScrollEnabled else {
            synthesizeMouseEvent(type: .leftMouseDragged, point: point)
            return
        }

        switch gestureState {
        case .idle:
            break

        case .pending(let startPoint, let startNorm, let startTime, let maxDisp):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)
            let updatedMaxDisp = max(maxDisp, distance)

            if distance >= slopThreshold {
                // 超過防誤觸容許位移，立即無延遲切入滑動捲動模式
                cancelLongPressTimer()
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])

                // 立即發送捲動開始事件（同時包含垂直與水平位移）
                postScrollEvent(deltaX: dx, deltaY: dy, phase: .began)
            } else {
                gestureState = .pending(
                    startPoint: startPoint,
                    startNormalized: startNorm,
                    startTime: startTime,
                    maxDisplacement: updatedMaxDisp
                )
            }

        case .scrolling(let lastPoint, var velocityTracker):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y

            velocityTracker.append((timestamp, point))
            // 保留最近 120ms 採樣點以計算精確釋放速度
            velocityTracker = velocityTracker.filter { timestamp - $0.0 < 0.12 }

            gestureState = .scrolling(lastPoint: point, velocityTracker: velocityTracker)

            // 即時發送雙向連續捲動更新
            postScrollEvent(deltaX: dx, deltaY: dy, phase: .changed)

        case .longPressTriggered:
            // 長按右鍵已觸發，手指滑動不發送左鍵拖曳或捲動，避免誤干擾
            break
        }
    }

    private func handleTouchUp(point: CGPoint, timestamp: TimeInterval) {
        cancelLongPressTimer()

        guard isTouchScrollEnabled else {
            synthesizeMouseEvent(type: .leftMouseUp, point: point)
            return
        }

        switch gestureState {
        case .idle:
            break

        case .pending(let startPoint, _, let startTime, let maxDisp):
            gestureState = .idle
            let elapsed = timestamp - startTime
            let liftDist = hypot(point.x - startPoint.x, point.y - startPoint.y)

            // 防止誤點擊判定：
            // 1. 接觸時長必須在有效點擊範圍內 (35ms ~ 320ms)
            // 2. 移動距離與全程最大位移皆未曾突破微小門檻 (slopThreshold)
            if elapsed >= minTapDuration && elapsed <= maxTapDuration && liftDist < slopThreshold && maxDisp < slopThreshold {
                synthesizeClick(at: startPoint)
            }

        case .scrolling(_, let velocityTracker):
            gestureState = .idle
            // 結束手勢滑動
            postScrollEvent(deltaX: 0, deltaY: 0, phase: .ended)

            // 計算手勢釋放時的即時雙向速度
            if velocityTracker.count >= 2,
               let first = velocityTracker.first,
               let last = velocityTracker.last {
                let dt = last.0 - first.0
                if dt > 0.015 {
                    let vx = (last.1.x - first.1.x) / dt
                    let vy = (last.1.y - first.1.y) / dt
                    let speed = hypot(vx, vy)
                    if speed >= minMomentumVelocity {
                        startMomentum(vx: vx, vy: vy)
                    }
                }
            }

        case .longPressTriggered:
            // 長按右鍵選單已開啟，手指抬起時重設狀態，不發送任何左鍵點擊
            gestureState = .idle
        }
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    // MARK: - 2D Momentum Simulation (支援垂直與水平雙向慣性捲動)

    private func startMomentum(vx: Double, vy: Double) {
        stopMomentum()
        let sign: Double = naturalScroll ? 1.0 : -1.0
        momentumVx = vx * sign * scrollSensitivity
        momentumVy = vy * sign * scrollSensitivity

        postMomentumScrollEvent(deltaX: 0, deltaY: 0, phase: .began)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] t in
            guard let self else {
                t.invalidate()
                return
            }
            self.tickMomentum(timer: t)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.momentumTimer = timer
    }

    private func tickMomentum(timer: Timer) {
        momentumVx *= friction
        momentumVy *= friction

        let speed = hypot(momentumVx, momentumVy)
        if speed < stopMomentumVelocity {
            stopMomentum()
            postMomentumScrollEvent(deltaX: 0, deltaY: 0, phase: .ended)
            return
        }

        let stepX = Int32(momentumVx * 0.016)
        let stepY = Int32(momentumVy * 0.016)

        if stepX != 0 || stepY != 0 {
            postMomentumScrollEvent(deltaX: stepX, deltaY: stepY, phase: .changed)
        }
    }

    private func stopMomentum() {
        if momentumTimer != nil {
            momentumTimer?.invalidate()
            momentumTimer = nil
            postMomentumScrollEvent(deltaX: 0, deltaY: 0, phase: .cancelled)
        }
    }

    // MARK: - Low-Level CGEvent Synthesis (2D Scroll & Click)

    /// 發送雙向捲動事件：wheel1 為垂直 (Y)，wheel2 為水平 (X)
    private func postScrollEvent(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        let sign: CGFloat = naturalScroll ? 1.0 : -1.0
        let totalY = deltaY * sign * scrollSensitivity + fractionalRemainderY
        let totalX = deltaX * sign * scrollSensitivity + fractionalRemainderX

        let intDy = Int32(totalY)
        let intDx = Int32(totalX)

        fractionalRemainderY = totalY - CGFloat(intDy)
        fractionalRemainderX = totalX - CGFloat(intDx)

        if phase == .changed && intDy == 0 && intDx == 0 {
            return
        }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: intDy,
            wheel2: intDx,
            wheel3: 0
        ) else { return }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        event.post(tap: .cghidEventTap)
    }

    /// 發送雙向慣性捲動事件
    private func postMomentumScrollEvent(deltaX: Int32, deltaY: Int32, phase: NSEvent.Phase) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else { return }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(phase.rawValue))
        event.post(tap: .cghidEventTap)
    }

    /// 合成標準左鍵輕點
    private func synthesizeClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        CGWarpMouseCursorPosition(point)

        let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        down?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: point,
                mouseButton: .left
            )
            up?.post(tap: .cghidEventTap)
        }
    }

    /// 合成 Windows 風格長按右鍵選單
    private func synthesizeRightClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        CGWarpMouseCursorPosition(point)

        let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        )
        down?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            let up = CGEvent(
                mouseEventSource: nil,
                mouseType: .rightMouseUp,
                mouseCursorPosition: point,
                mouseButton: .right
            )
            up?.post(tap: .cghidEventTap)
        }
    }

    private func synthesizeMouseEvent(type: CGEventType, point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }
}
