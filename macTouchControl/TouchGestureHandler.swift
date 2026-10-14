//
//  TouchGestureHandler.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import Foundation
import CoreGraphics
import AppKit

/// 外接觸控螢幕專用觸控手勢處理引擎
/// 1. 平板／手機風格雙向捲動（2D Direct Manipulation Scrolling）：上下與左右滑動均直接跟手，零延遲反映
/// 2. 換向即刻反應（Instant Direction Reversal）：滑動時突然反向或煞車反甩，零延遲瞬間響應，清空反向次像素與慣性歷史
/// 3. 滑動三重防誤觸鎖定（Click Lock Engine）：
///    - 手勢一旦進入滑動（hasScrolledInCurrentGesture == true），抬手絕對鎖死 Click
///    - 捲動活躍工作階段（isScrollSessionActive，滑動後 400ms 內），所有落指與抬起一律鎖定 Click，杜絕煞車或連滑誤開連結
///    - 捲動開始前強制發送 leftMouseUp（Anti-Highlight），徹底阻斷文字反白拖曳
/// 4. Windows 風格長按觸發右鍵：定點長按約 0.45 秒呼叫右鍵捷徑選單（預設開啟，可自由切換）
/// 5. 2D 物理慣性滑行模擬器（相容 macOS 原生滾動動畫終止標準）
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

    /// 滑動靈敏度倍率
    var scrollSensitivity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "macTouchControl.scrollSensitivity")
        }
    }

    /// 是否啟用 Windows 風格定點長按觸發右鍵（預設開啟）
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

    // MARK: - Precision Thresholds & Click Lock Engine

    /// 本次手勢是否已進入過捲動狀態。一旦捲動過，本次手勢結束時絕對鎖死 Click，嚴禁任何點擊
    private(set) var hasScrolledInCurrentGesture: Bool = false

    /// 上次捲動發生的時間戳（包含連續手勢捲動與慣性捲動）
    private(set) var lastScrollTimestamp: TimeInterval = 0

    /// 捲動冷卻鎖定視窗（400ms）：在捲動發生後的 400ms 內，點擊判定全面鎖定，所有落指抬起均視為捲動煞車或換向調整，絕不誤觸點擊
    private let scrollClickLockDuration: TimeInterval = 0.40

    /// 是否處於捲動活躍工作階段（此時點擊被完全鎖定）
    var isScrollSessionActive: Bool {
        ProcessInfo.processInfo.systemUptime - lastScrollTimestamp < scrollClickLockDuration
    }

    /// 冷啟動時的滑動門檻 (3.5pt，極致跟手，杜絕卡頓感)
    private let initialSlopThreshold: CGFloat = 3.5

    /// 處於活躍捲動工作階段 (Scroll Session) 時的滑動門檻 (1.0pt，手指一動即刻雙向反應，零遲滯)
    private let activeSessionSlopThreshold: CGFloat = 1.0

    /// 取得目前手勢應採用的滑動門檻
    private var currentSlopThreshold: CGFloat {
        isScrollSessionActive ? activeSessionSlopThreshold : initialSlopThreshold
    }

    /// 長按右鍵門檻：長按 0.45 秒觸發右鍵（如同 Windows / Surface 觸控體驗）
    private let longPressThreshold: TimeInterval = 0.45

    /// 有效輕點最短時間 (40ms)，過濾硬體電容抖動造成的幽靈誤點擊
    private let minTapDuration: TimeInterval = 0.04

    /// 有效輕點最長時間 (200ms)，超過此時間未滑動亦不判定為誤點擊
    private let maxTapDuration: TimeInterval = 0.20

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
        cancelLongPressTimer()

        // 檢查是否處於慣性滑行中
        let wasMomentumActive = (momentumTimer != nil)
        stopMomentum() // 發送 phase: .ended 確保系統即刻煞車，不與後續反向滑動衝突

        hasScrolledInCurrentGesture = false
        fractionalRemainderX = 0
        fractionalRemainderY = 0

        guard isTouchScrollEnabled else {
            // 若關閉平板滑動模式，走傳統直接滑鼠拖曳
            synthesizeMouseEvent(type: .leftMouseDown, point: point)
            return
        }

        // 若前次處於慣性滑行中，本次落指立即發揮煞車作用，同時具備一觸即發的換向反應能力
        if wasMomentumActive {
            lastScrollTimestamp = timestamp
            gestureState = .stoppingMomentum(point: point)
            return
        }

        let inActiveSession = isScrollSessionActive

        gestureState = .pending(
            startPoint: point,
            startNormalized: normalized,
            startTime: timestamp,
            maxDisplacement: 0
        )

        // 僅在非連續捲動冷卻時才排程長按右鍵，避免連續滑動閱覽時誤觸發右鍵選單
        if isLongPressRightClickEnabled && !inActiveSession {
            let timer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
                guard let self else { return }
                if case .pending(let startPoint, _, _, let maxDisp) = self.gestureState {
                    if maxDisp < self.initialSlopThreshold && !self.isScrollSessionActive {
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
            let dist = hypot(dx, dy)

            // 碰觸煞車後，手指只要微幅移動超過 1.0pt（無遲滯），立刻開始換向滑動
            if dist >= activeSessionSlopThreshold {
                hasScrolledInCurrentGesture = true
                lastScrollTimestamp = timestamp
                cancelAnyMouseDrag(at: point)
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])
                postScrollEvent(deltaX: dx, deltaY: dy, phase: .began)
            }

        case .pending(let startPoint, let startNorm, let startTime, let maxDisp):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)
            let updatedMaxDisp = max(maxDisp, distance)
            let threshold = currentSlopThreshold

            if distance >= threshold {
                // 超過滑動門檻，立即無延遲切入滑動模式，並鎖死點擊
                cancelLongPressTimer()
                hasScrolledInCurrentGesture = true
                lastScrollTimestamp = timestamp

                // 重要：在發送任何捲動事件之前，確保滑鼠左鍵已強制釋放，徹底阻斷滑鼠拖曳文字反白 (Anti-Highlight)
                cancelAnyMouseDrag(at: point)

                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])

                // 立即發送第一筆捲動事件（保留完整位移量，起步絕不卡頓）
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

            hasScrolledInCurrentGesture = true
            lastScrollTimestamp = timestamp

            // 【換向即刻反應邏輯】：
            // 若手指移動方向突然反轉，立即截斷速度追蹤器中的舊反向樣本，杜絕慣性反拉
            if let lastSample = velocityTracker.last {
                let prevDx = point.x - lastSample.1.x
                let prevDy = point.y - lastSample.1.y
                if (dy > 0 && prevDy < -0.5) || (dy < 0 && prevDy > 0.5) ||
                   (dx > 0 && prevDx < -0.5) || (dx < 0 && prevDx > 0.5) {
                    velocityTracker.removeAll()
                }
            }

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
            lastScrollTimestamp = timestamp
            // 煞車手勢抬起，絕對不觸發任何點擊

        case .pending(let startPoint, _, let startTime, let maxDisp):
            gestureState = .idle
            let elapsed = timestamp - startTime
            let liftDist = hypot(point.x - startPoint.x, point.y - startPoint.y)

            // 【極致三重防誤觸鎖定 Click】：
            // 1. 若手勢曾進入捲動狀態（hasScrolledInCurrentGesture == true），絕對鎖死點擊
            // 2. 若處於捲動活躍工作階段（isScrollSessionActive == true，400ms 內曾滑動），絕對鎖死點擊
            // 3. 接觸時長與位移必須在極為嚴格的點擊範圍內（40ms ~ 200ms，位移 < initialSlopThreshold）
            if !hasScrolledInCurrentGesture &&
               !isScrollSessionActive &&
               elapsed >= minTapDuration &&
               elapsed <= maxTapDuration &&
               liftDist < initialSlopThreshold &&
               maxDisp < initialSlopThreshold {
                synthesizeClick(at: startPoint)
            }

        case .scrolling(_, let velocityTracker):
            gestureState = .idle
            lastScrollTimestamp = timestamp

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
            return
        }

        let stepX = Int32(momentumVx * 0.016)
        let stepY = Int32(momentumVy * 0.016)

        if stepX != 0 || stepY != 0 {
            lastScrollTimestamp = ProcessInfo.processInfo.systemUptime
            postMomentumScrollEvent(deltaX: stepX, deltaY: stepY, phase: .changed)
        }
    }

    private func stopMomentum() {
        if momentumTimer != nil {
            momentumTimer?.invalidate()
            momentumTimer = nil
            momentumVx = 0
            momentumVy = 0
            lastScrollTimestamp = ProcessInfo.processInfo.systemUptime
            // 發送 phase: .ended 立即通知 macOS 系統終止慣性滑行，不延遲後續反向滑動
            postMomentumScrollEvent(deltaX: 0, deltaY: 0, phase: .ended)
        }
    }

    // MARK: - Low-Level CGEvent Synthesis (2D Scroll & Click)

    /// 發送雙向捲動事件：wheel1 為垂直 (Y)，wheel2 為水平 (X)
    private func postScrollEvent(deltaX: CGFloat, deltaY: CGFloat, phase: NSEvent.Phase) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        // 【換向即刻反應】：若移動方向與殘存的次像素方向相反，立即歸零殘存次像素，防止舊方向抵消反向位移
        if (deltaY > 0 && fractionalRemainderY < 0) || (deltaY < 0 && fractionalRemainderY > 0) {
            fractionalRemainderY = 0
        }
        if (deltaX > 0 && fractionalRemainderX < 0) || (deltaX < 0 && fractionalRemainderX > 0) {
            fractionalRemainderX = 0
        }

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

    /// 強制取消任何可能的滑鼠拖曳狀態，避免滑動時產生文字反白選取 (Anti-Highlight)
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
        CGWarpMouseCursorPosition(point)
        let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
        event?.post(tap: .cghidEventTap)
    }
}
