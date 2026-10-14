//
//  TouchGestureHandler.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import Foundation
import CoreGraphics
import AppKit

/// 平板風格觸控手勢處理引擎
/// 核心設計：
/// 1. 零延遲跟手：即時雙向捲動 (wheel1 垂直, wheel2 水平)，無佇列延遲
/// 2. 嚴密防誤點擊與防誤反白 (Anti-Misclick & Anti-Highlight)：
///    - 捲動開始時強制發送 leftMouseUp 阻斷任何拖曳反白選取文字
///    - 點擊事件 (synthesizeClick) 採原子性同步發送，固定 clickState = 1，絕不觸發雙擊/三擊文字反白
///    - 慣性捲動中落指煞車中斷後，抬手絕對不觸發誤點擊
/// 3. Windows 風格長按觸發右鍵：按住約 0.45 秒觸發快捷選單，預設開啟且使用者可自由關閉
/// 4. 2D 物理慣性滑行模擬器 (帶摩擦力衰減)
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

    /// 長按定點觸發右鍵選單（如同 Windows 體驗，預設開啟，使用者可自由選擇關閉）
    var isLongPressRightClickEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isLongPressRightClickEnabled, forKey: "macTouchControl.longPressRightClickEnabled")
        }
    }

    // MARK: - Internal Gesture State

    private enum GestureState {
        case idle
        /// 手指剛落下，尚未判定為點擊、滑動或長按
        case pending(startPoint: CGPoint, startNormalized: CGPoint, startTime: TimeInterval, maxDisplacement: CGFloat)
        /// 觸碰剛好用來煞停慣性滑行（碰觸煞車），抬手時嚴禁誤點擊
        case stoppingMomentum(point: CGPoint)
        /// 正在進行雙向（垂直與水平）滑動捲動
        case scrolling(lastPoint: CGPoint, velocityTracker: [(TimeInterval, CGPoint)])
        /// 長按時間已達標並觸發右鍵
        case longPressTriggered(point: CGPoint)
    }

    private var gestureState: GestureState = .idle
    private var longPressTimer: Timer?

    // MARK: - Precision Thresholds (防誤觸與零延遲跟手參數)

    /// 滑動識別閥值：手指移動超過 6.0 點即判定為滑動，精確區隔定點輕點與滑動
    private let slopThreshold: CGFloat = 6.0

    /// 長按右鍵閥值：長按 0.45 秒觸發右鍵（如同 Windows / Surface 觸控體驗）
    private let longPressThreshold: TimeInterval = 0.45

    /// 有效輕點最短時間 (40ms)，過濾硬體電容抖動造成的幽靈誤點擊
    private let minTapDuration: TimeInterval = 0.04

    /// 有效輕點最長時間 (220ms)，超過此時間未滑動亦不判定為誤點擊
    private let maxTapDuration: TimeInterval = 0.22

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
    private var wasMomentumActiveOnTouchDown: Bool = false

    // 次像素累加器（垂直與水平）
    private var fractionalRemainderX: CGFloat = 0
    private var fractionalRemainderY: CGFloat = 0

    init() {
        // 註冊系統預設值：滑動模式、自然捲動與長按右鍵預設必須開啟
        UserDefaults.standard.register(defaults: [
            "macTouchControl.touchScrollEnabled": true,
            "macTouchControl.naturalScroll": true,
            "macTouchControl.scrollSensitivity": 1.0,
            "macTouchControl.longPressRightClickEnabled": true
        ])

        self.isTouchScrollEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.touchScrollEnabled")
        self.naturalScroll = UserDefaults.standard.bool(forKey: "macTouchControl.naturalScroll")
        self.isLongPressRightClickEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.longPressRightClickEnabled")

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
        wasMomentumActiveOnTouchDown = false

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

        // 若前次處於慣性滑行中，本次落指僅作「煞車／停下畫面」用途，絕對不觸發後續誤點擊
        if wasMomentumActiveOnTouchDown {
            wasMomentumActiveOnTouchDown = false
            gestureState = .stoppingMomentum(point: point)
            return
        }

        gestureState = .pending(
            startPoint: point,
            startNormalized: normalized,
            startTime: timestamp,
            maxDisplacement: 0
        )

        // Windows 觸控風格：長按定點約 0.45 秒觸發右鍵選單（需設定開啟）
        if isLongPressRightClickEnabled {
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
    }

    private func handleTouchMoved(point: CGPoint, timestamp: TimeInterval) {
        guard isTouchScrollEnabled else {
            synthesizeMouseEvent(type: .leftMouseDragged, point: point)
            return
        }

        switch gestureState {
        case .idle:
            break

        case .stoppingMomentum(let startPt):
            let dx = point.x - startPt.x
            let dy = point.y - startPt.y
            if hypot(dx, dy) >= slopThreshold {
                cancelAnyMouseDrag(at: point)
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])
                postScrollEvent(deltaX: dx, deltaY: dy, phase: .began)
            }

        case .pending(let startPoint, let startNorm, let startTime, let maxDisp):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)
            let updatedMaxDisp = max(maxDisp, distance)

            if distance >= slopThreshold {
                // 超過防誤觸容許位移，立即無延遲切入滑動捲動模式
                cancelLongPressTimer()

                // 重要：在發送任何捲動事件之前，確保滑鼠左鍵已強制釋放，徹底阻斷滑鼠拖曳文字反白 (Anti-Highlight)
                cancelAnyMouseDrag(at: point)

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

        case .stoppingMomentum:
            gestureState = .idle
            // 碰觸純粹作為煞車中斷慣性滑行，手指抬起時絕對不觸發點擊

        case .pending(let startPoint, _, let startTime, let maxDisp):
            gestureState = .idle
            let elapsed = timestamp - startTime
            let liftDist = hypot(point.x - startPoint.x, point.y - startPoint.y)

            // 防止誤點擊判定：
            // 1. 接觸時長必須在有效點擊範圍內 (40ms ~ 220ms)
            // 2. 移動距離與全程最大位移皆未曾突破門檻 (slopThreshold)
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
            wasMomentumActiveOnTouchDown = true
            momentumTimer?.invalidate()
            momentumTimer = nil
            momentumVx = 0
            momentumVy = 0
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

    /// 強制釋放可能處於按住狀態的滑鼠左鍵，防止滑動時拖曳選取／文字反白 (Anti-Highlight)
    private func cancelAnyMouseDrag(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        up.setIntegerValueField(.mouseEventClickState, value: 0)
        up.post(tap: .cghidEventTap)
    }

    /// 合成標準左鍵輕點（原子性同步發送，嚴防拖曳反白與連續點擊選取文字）
    private func synthesizeClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        CGWarpMouseCursorPosition(point)

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        // 明確將點擊次數固定為 1，防止 macOS 連續點擊計數器判定為 Double Click / Triple Click 誤反白選取文字
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// 合成 Windows 風格長按右鍵選單（原子性同步發送）
    private func synthesizeRightClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        CGWarpMouseCursorPosition(point)

        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseUp,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else { return }

        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
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
