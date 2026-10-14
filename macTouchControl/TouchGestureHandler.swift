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

/// 負責處理觸摸屏 Mobile/Tablet 滑動手勢、輕點點擊、長按拖曳與慣性滾動
@Observable
@MainActor
final class TouchGestureHandler {
    static let shared = TouchGestureHandler()

    // MARK: - User Settings

    /// 是否啟用手機／平板風格的觸摸屏滑動體驗
    var isTouchScrollEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isTouchScrollEnabled, forKey: "macTouchControl.touchScrollEnabled")
        }
    }

    /// 自然滑動方向（內容直接跟隨手指移動）
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
        case pending(startPoint: CGPoint, startNormalized: CGPoint, startTime: TimeInterval)
        case scrolling(lastPoint: CGPoint, velocityTracker: [(TimeInterval, CGPoint)])
        case dragging(lastPoint: CGPoint)
    }

    private var gestureState: GestureState = .idle
    private var holdTimer: Timer?

    // 觸控手勢識別常數
    private let slopThreshold: CGFloat = 8.0          // 超過此距離即判定為滑動而非點擊
    private let dragHoldTimeout: TimeInterval = 0.35   // 按住不動超過此時間轉為直接拖曳模式 (以利拖曳視窗或滑桿)
    private let friction: Double = 0.94                // 慣性滑動摩擦力衰減係數
    private let minMomentumVelocity: Double = 80.0     // 觸發慣性滑動的最低釋放速度 (px/s)
    private let stopMomentumVelocity: Double = 8.0     // 慣性停止速度 (px/s)

    // 慣性滑動狀態
    private var momentumTimer: Timer?
    private var momentumVx: Double = 0
    private var momentumVy: Double = 0

    // 次像素累加器
    private var fractionalRemainderX: CGFloat = 0
    private var fractionalRemainderY: CGFloat = 0

    init() {
        if UserDefaults.standard.object(forKey: "macTouchControl.touchScrollEnabled") != nil {
            self.isTouchScrollEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.touchScrollEnabled")
        } else {
            self.isTouchScrollEnabled = true
        }

        if UserDefaults.standard.object(forKey: "macTouchControl.naturalScroll") != nil {
            self.naturalScroll = UserDefaults.standard.bool(forKey: "macTouchControl.naturalScroll")
        } else {
            self.naturalScroll = true
        }

        let savedSensitivity = UserDefaults.standard.double(forKey: "macTouchControl.scrollSensitivity")
        if savedSensitivity > 0 {
            self.scrollSensitivity = savedSensitivity
        } else {
            self.scrollSensitivity = 1.0
        }
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
        // 中斷進行中的慣性滾動（如同平板螢幕一碰即停）
        stopMomentum()

        cancelHoldTimer()
        fractionalRemainderX = 0
        fractionalRemainderY = 0

        guard isTouchScrollEnabled else {
            // 若關閉平板滑動模式，走傳統直接滑鼠拖曳
            gestureState = .dragging(lastPoint: point)
            synthesizeMouseEvent(type: .leftMouseDown, point: point)
            return
        }

        gestureState = .pending(startPoint: point, startNormalized: normalized, startTime: timestamp)

        // 啟動長按檢測計時器：若按住不動超過 dragHoldTimeout 則切換為滑鼠拖曳（便於拖曳視窗標題列、選取或拉滑桿）
        let timer = Timer.scheduledTimer(withTimeInterval: dragHoldTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .pending(let startPoint, _, _) = self.gestureState {
                self.gestureState = .dragging(lastPoint: startPoint)
                self.synthesizeMouseEvent(type: .leftMouseDown, point: startPoint)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.holdTimer = timer
    }

    private func handleTouchMoved(point: CGPoint, timestamp: TimeInterval) {
        switch gestureState {
        case .idle:
            break

        case .pending(let startPoint, _, _):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)

            if distance >= slopThreshold {
                // 超過點擊容許位移，正式判定為「滑動手勢」
                cancelHoldTimer()
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])

                // 發送滑動開始事件
                postScrollEvent(deltaX: dx, deltaY: dy, phase: .began)
            }

        case .scrolling(let lastPoint, var velocityTracker):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y

            velocityTracker.append((timestamp, point))
            // 僅保留最近 120ms 的採樣點以計算精準釋放速度
            velocityTracker = velocityTracker.filter { timestamp - $0.0 < 0.12 }

            gestureState = .scrolling(lastPoint: point, velocityTracker: velocityTracker)

            postScrollEvent(deltaX: dx, deltaY: dy, phase: .changed)

        case .dragging(let lastPoint):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            if hypot(dx, dy) > 0.5 {
                synthesizeMouseEvent(type: .leftMouseDragged, point: point)
                gestureState = .dragging(lastPoint: point)
            }
        }
    }

    private func handleTouchUp(point: CGPoint, timestamp: TimeInterval) {
        cancelHoldTimer()

        switch gestureState {
        case .idle:
            break

        case .pending(let startPoint, _, _):
            // 判定為輕點（Tap / Click）
            gestureState = .idle
            synthesizeClick(at: startPoint)

        case .scrolling(_, let velocityTracker):
            gestureState = .idle
            // 結束滑動
            postScrollEvent(deltaX: 0, deltaY: 0, phase: .ended)

            // 計算手勢釋放時的即時速度
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

        case .dragging:
            gestureState = .idle
            synthesizeMouseEvent(type: .leftMouseUp, point: point)
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    // MARK: - Momentum Simulation

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

    // MARK: - Low-Level CGEvent Synthesis

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

        // 延遲 15ms 發送 MouseUp，確保 DOM 及 UI 事件識別點擊完整
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
