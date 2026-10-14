//
//  TouchGestureHandler.swift
//  macTouchControl
//
//  Created by LeeChunYen on 14/10/2026.
//

import Foundation
import CoreGraphics
import AppKit

// MARK: - Background Window Frame Cache (0 毫秒極速快取引擎)

/// 背景全域視窗快取引擎，提供 0 毫秒極速查詢，絕不阻塞觸控主執行緒
final class WindowFrameCache: @unchecked Sendable {
    static let shared = WindowFrameCache()

    private let lock = NSLock()
    private var titleBarRects: [CGRect] = []
    private var lastUpdateTime: TimeInterval = 0
    private var isUpdating: Bool = false

    private init() {
        refreshAsync()

        // 監聽前台程式切換與視窗重繪通知
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshAsync()
        }
    }

    /// 在背景線程異步刷新所有可見視窗頂部標題列邊界
    func refreshAsync() {
        guard !isUpdating else { return }
        isUpdating = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            defer { self?.isUpdating = false }
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

            var newRects: [CGRect] = []
            for window in windowList {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                      let x = boundsDict["X"] as? CGFloat,
                      let y = boundsDict["Y"] as? CGFloat,
                      let w = boundsDict["Width"] as? CGFloat,
                      let h = boundsDict["Height"] as? CGFloat else { continue }

                // 標題列高度預設約 52pt
                let titleBarHeight: CGFloat = 52.0
                let titleBarRect = CGRect(x: x, y: y, width: w, height: min(h, titleBarHeight))
                newRects.append(titleBarRect)
            }

            self?.lock.lock()
            self?.titleBarRects = newRects
            self?.lastUpdateTime = ProcessInfo.processInfo.systemUptime
            self?.lock.unlock()
        }
    }

    /// 0 毫秒高速判定落指點是否位於任何視窗標題列（排除左上角交通燈）
    func isTitleBar(at point: CGPoint) -> Bool {
        // 定期背景更新
        if ProcessInfo.processInfo.systemUptime - lastUpdateTime > 1.0 {
            refreshAsync()
        }

        lock.lock()
        let rects = titleBarRects
        lock.unlock()

        for rect in rects {
            if rect.contains(point) {
                // 排除視窗左上角紅黃綠交通燈按鈕區域（寬約 75pt）
                let trafficLights = CGRect(x: rect.origin.x, y: rect.origin.y, width: 75, height: rect.height)
                if !trafficLights.contains(point) {
                    return true
                }
            }
        }
        return false
    }
}

// MARK: - Touch Gesture Handler Engine

/// 外接觸控螢幕專用觸控手勢處理引擎
/// 1. 平板／手機風格雙向捲動（2D Direct Manipulation Scrolling）：上下與左右滑動均直接跟手，零延遲反映
/// 2. 視窗拖曳與「按著拖」支援（Window Title Bar Drag & Press-and-Hold Drag）：
///    - 觸摸任何視窗頂部標題列直接滑動即可拖曳移動視窗（Direct Window Dragging）
///    - 任何區域定點長按（約 0.38s）後移動，無縫切入「按著拖」（Press-and-Hold Drag），可自由拖曳視窗、物件、滑桿或文字選取
/// 3. Windows 風格長按觸發右鍵：定點長按後若「抬起手指」，即觸發右鍵捷徑選單（長按後若「滑動」則自動轉為拖曳，二者完美互不衝突）
/// 4. 游標與視窗命中焦點同步（WindowServer Hit-Test Pointer Sync）：落指與捲動時即時同步更新 WindowServer 指針目標
/// 5. 換向即刻反應（Instant Direction Reversal）：滑動時突然反向或煞車反甩，零延遲瞬間響應，清空反向次像素與慣性歷史
/// 6. 精確浮點次像素輸出（1:1 True Pixel Scroll & Sensitivity）：直接填寫 fixedPtDelta 與 pointDelta，速度拉條完全真實生效，絲滑流暢不卡頓
/// 7. 滑動絕對防誤觸（Bulletproof Click Lock & Anti-Highlight）：手勢一旦位移即鎖死 Click，白名單事件簽名（0x544F5543）杜絕幽靈誤點擊
/// 8. 2D 物理慣性滑行模擬器（相容 macOS 原生滾動動畫終止標準）
@Observable
@MainActor
final class TouchGestureHandler {
    static let shared = TouchGestureHandler()

    /// 合成白名單事件簽名（"TOUC" in hex: 0x544F5543），供 CGEventTap 識別合法點擊與拖曳
    static let synthesizedEventSignature: Int64 = 0x544F5543

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

    /// 滑動靈敏度倍率（直接作用於浮點捲動點數）
    var scrollSensitivity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "macTouchControl.scrollSensitivity")
        }
    }

    /// 是否啟用 Windows 風格定點長按觸發右鍵（預設開啟）
    var isLongPressRightClickEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isLongPressRightClickEnabled, forKey: "macTouchControl.longPressRightClickEnabled")
            if !isLongPressRightClickEnabled {
                cancelLongPressTimer()
            }
        }
    }

    // MARK: - Internal Gesture State

    private enum GestureState {
        case idle
        /// 手指剛落下，尚未判定為點擊、滑動、長按或拖曳
        case pending(startPoint: CGPoint, startNormalized: CGPoint, startTime: TimeInterval, maxDisplacement: CGFloat, isTitleBar: Bool)
        /// 觸碰剛好用來煞停慣性滑行（碰觸煞車），抬手時嚴禁誤點擊
        case stoppingMomentum(point: CGPoint)
        /// 正在進行雙向（垂直與水平）滑動捲動
        case scrolling(lastPoint: CGPoint, velocityTracker: [(TimeInterval, CGPoint)])
        /// 定點長按已就緒（若抬手則觸發右鍵；若手指移動則無縫切換為「按著拖曳」）
        case longPressArmed(point: CGPoint)
        /// 正在進行物件或視窗拖曳（滑鼠左鍵按住拖曳）
        case dragging(lastPoint: CGPoint)
    }

    private var gestureState: GestureState = .idle
    private var longPressTimer: Timer?

    // MARK: - Precision Thresholds & Click Lock Engine

    /// 本次手勢是否已進入過捲動狀態。一旦捲動過，本次手勢結束時絕對鎖死 Click，嚴禁任何點擊
    private(set) var hasScrolledInCurrentGesture: Bool = false

    /// 上次捲動發生的時間戳（包含連續手勢捲動與慣性捲動）
    private(set) var lastScrollTimestamp: TimeInterval = 0

    /// 上次捲動的目標螢幕全域座標（供慣性滑行與命中測試定位）
    private var lastScrollPoint: CGPoint = .zero

    /// 捲動冷卻鎖定視窗（450ms）：在捲動發生後的 450ms 內，點擊判定全面鎖定，所有落指抬起均視為捲動煞車或換向調整，絕不誤觸點擊
    private let scrollClickLockDuration: TimeInterval = 0.45

    /// 是否處於捲動活躍工作階段（此時點擊被完全鎖定）
    var isScrollSessionActive: Bool {
        ProcessInfo.processInfo.systemUptime - lastScrollTimestamp < scrollClickLockDuration
    }

    /// 手指輕點有效位移容許範圍 (8.0pt)：人體手指指腹接觸面約 10~15mm，落指與抬起時的重心自然微移在 8pt 內均判定為有效點擊，杜絕誤當微小滑動
    private let tapSlopThreshold: CGFloat = 8.0

    /// 冷啟動時的滑動門檻 (7.0pt，位移超過 7pt 明顯屬於滑動意圖，立即轉入捲動並鎖定點擊)
    private let initialSlopThreshold: CGFloat = 7.0

    /// 處於活躍捲動工作階段 (Scroll Session) 時的滑動門檻 (3.0pt，連續劃動起步極度跟手)
    private let activeSessionSlopThreshold: CGFloat = 3.0

    /// 取得目前手勢應採用的滑動門檻
    private var currentSlopThreshold: CGFloat {
        isScrollSessionActive ? activeSessionSlopThreshold : initialSlopThreshold
    }

    /// 定點長按門檻：長按約 0.38 秒（如同 Windows / Surface 觸控體驗）
    private let longPressThreshold: TimeInterval = 0.38

    /// 有效輕點最短時間 (20ms)，過濾極端硬體噪訊
    private let minTapDuration: TimeInterval = 0.02

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

        // 核心同步 1：背景異步啟動落指位置下方的應用程式，消除跨螢幕焦點滯留與 macOS 背景 App Nap 節流
        activateAppUnder(point: point)

        // 核心同步 2：落指時立即更新 WindowServer 命中焦點與游標位置
        updateWindowServerPointer(at: point)
        lastScrollPoint = point

        // 檢查是否處於慣性滑行中
        let wasMomentumActive = (momentumTimer != nil)
        stopMomentum() // 發送 phase: .ended 確保系統即刻煞車，不與後續反向滑動衝突

        hasScrolledInCurrentGesture = false
        fractionalRemainderX = 0
        fractionalRemainderY = 0

        guard isTouchScrollEnabled else {
            // 若關閉平板滑動模式，走傳統直接滑鼠拖曳
            postMouseDown(at: point)
            return
        }

        // 若前次處於慣性滑行中，本次落指立即發揮煞車作用
        if wasMomentumActive {
            lastScrollTimestamp = timestamp
            gestureState = .stoppingMomentum(point: point)
            return
        }

        let inActiveSession = isScrollSessionActive
        // 0 毫秒記憶體極速快取判定是否命中視窗標題列
        let onTitleBar = WindowFrameCache.shared.isTitleBar(at: point)

        gestureState = .pending(
            startPoint: point,
            startNormalized: normalized,
            startTime: timestamp,
            maxDisplacement: 0,
            isTitleBar: onTitleBar
        )

        // 若非連續快速滑動冷卻中，排程定點長按計時器（用於觸發右鍵或就緒「按著拖曳」）
        if !inActiveSession {
            let timer = Timer.scheduledTimer(withTimeInterval: longPressThreshold, repeats: false) { [weak self] _ in
                guard let self else { return }
                if case .pending(let startPoint, _, _, let maxDisp, _) = self.gestureState {
                    if maxDisp < self.tapSlopThreshold && !self.isScrollSessionActive {
                        // 定點長按時間已達標：就緒狀態。若抬手則為右鍵；若手指移動則無縫轉為「按著拖」！
                        self.gestureState = .longPressArmed(point: startPoint)
                    }
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.longPressTimer = timer
        }
    }

    private func handleTouchMoved(point: CGPoint, timestamp: TimeInterval) {
        guard isTouchScrollEnabled else {
            postMouseDragged(to: point)
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
                lastScrollPoint = point
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])
                postScrollEvent(deltaX: dx, deltaY: dy, at: point, phase: .began)
            }

        case .pending(let startPoint, let startNorm, let startTime, let maxDisp, let isTitleBar):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)
            let updatedMaxDisp = max(maxDisp, distance)
            let threshold = currentSlopThreshold

            if distance >= threshold {
                cancelLongPressTimer()

                if isTitleBar {
                    // 【視窗標題列直接拖曳】：手指在標題列滑動，直接進行視窗拖曳！
                    gestureState = .dragging(lastPoint: point)
                    postMouseDown(at: startPoint)
                    postMouseDragged(to: point)
                } else {
                    // 【內容區域滑動】：超過極小門檻 (2.0pt)，無延遲切入雙向平板滑動捲動模式
                    hasScrolledInCurrentGesture = true
                    lastScrollTimestamp = timestamp
                    lastScrollPoint = point

                    gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])

                    // 立即發送第一筆捲動事件（保留完整位移量，起步絕不卡頓）
                    postScrollEvent(deltaX: dx, deltaY: dy, at: point, phase: .began)
                }
            } else {
                gestureState = .pending(
                    startPoint: startPoint,
                    startNormalized: startNorm,
                    startTime: startTime,
                    maxDisplacement: updatedMaxDisp,
                    isTitleBar: isTitleBar
                )
            }

        case .longPressArmed(let startPoint):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)

            if distance >= initialSlopThreshold {
                // 【按著拖 (Press-and-Hold Drag)】：
                // 使用者定點長按後開始移動手指，立刻轉入左鍵按住拖曳模式！
                // 可自由拖曳任何視窗、檔案、文字選取或滑桿！
                gestureState = .dragging(lastPoint: point)
                postMouseDown(at: startPoint)
                postMouseDragged(to: point)
            }

        case .dragging:
            // 正在進行物件或視窗拖曳，發送連續專用左鍵拖曳事件
            gestureState = .dragging(lastPoint: point)
            postMouseDragged(to: point)

        case .scrolling(let lastPoint, var velocityTracker):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y

            hasScrolledInCurrentGesture = true
            lastScrollTimestamp = timestamp
            lastScrollPoint = point

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
            postScrollEvent(deltaX: dx, deltaY: dy, at: point, phase: .changed)
        }
    }

    private func handleTouchUp(point: CGPoint, timestamp: TimeInterval) {
        cancelLongPressTimer()

        guard isTouchScrollEnabled else {
            postMouseUp(at: point)
            return
        }

        switch gestureState {
        case .idle:
            break

        case .stoppingMomentum:
            gestureState = .idle
            lastScrollTimestamp = timestamp
            // 煞車手勢抬起，絕對不觸發任何點擊

        case .pending(let startPoint, _, let startTime, let maxDisp, _):
            gestureState = .idle
            let elapsed = timestamp - startTime
            let liftDist = hypot(point.x - startPoint.x, point.y - startPoint.y)

            // 【自然穩健且精確的點擊判定】：
            // 1. 若手勢曾進入捲動狀態（hasScrolledInCurrentGesture == true），絕對鎖死點擊
            // 2. 接觸時間在 0.02s 至 longPressThreshold (0.38s) 之間，徹底消除 220ms~380ms 的盲區死角
            // 3. 最大位移與抬手位移均在指腹容許範圍內 (< tapSlopThreshold (8.0pt))
            if !hasScrolledInCurrentGesture &&
               elapsed >= minTapDuration &&
               elapsed < longPressThreshold &&
               liftDist < tapSlopThreshold &&
               maxDisp < tapSlopThreshold {
                synthesizeClick(at: startPoint)
            }

        case .longPressArmed(let startPoint):
            gestureState = .idle
            // 【長按抬手觸發右鍵】：
            // 使用者在定點長按達標後抬起手指（未進行拖曳），觸發 Windows 風格右鍵選單！
            if isLongPressRightClickEnabled {
                synthesizeRightClick(at: startPoint)
            }

        case .dragging:
            // 【拖曳結束釋放】：手指抬起，發送 leftMouseUp 結束視窗或物件拖曳
            gestureState = .idle
            postMouseUp(at: point)
            WindowFrameCache.shared.refreshAsync()

        case .scrolling(_, let velocityTracker):
            gestureState = .idle
            lastScrollTimestamp = timestamp
            lastScrollPoint = point

            // 結束手勢滑動
            postScrollEvent(deltaX: 0, deltaY: 0, at: point, phase: .ended)

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
                        startMomentum(vx: vx, vy: vy, at: point)
                    }
                }
            }
        }
    }

    private func cancelLongPressTimer() {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    // MARK: - 2D Momentum Simulation (支援垂直與水平雙向慣性捲動)

    private func startMomentum(vx: Double, vy: Double, at point: CGPoint) {
        stopMomentum()
        lastScrollPoint = point
        let sign: Double = naturalScroll ? 1.0 : -1.0
        momentumVx = vx * sign * scrollSensitivity
        momentumVy = vy * sign * scrollSensitivity

        postMomentumScrollEvent(deltaX: 0, deltaY: 0, at: point, phase: .began)

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

        let stepX = momentumVx * 0.016
        let stepY = momentumVy * 0.016

        if abs(stepX) > 0.1 || abs(stepY) > 0.1 {
            lastScrollTimestamp = ProcessInfo.processInfo.systemUptime
            postMomentumScrollEvent(deltaX: CGFloat(stepX), deltaY: CGFloat(stepY), at: lastScrollPoint, phase: .changed)
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
            postMomentumScrollEvent(deltaX: 0, deltaY: 0, at: lastScrollPoint, phase: .ended)
        }
    }

    // MARK: - Low-Level CGEvent Synthesis (2D Scroll, Click & Drag)

    /// 確保落指時目標螢幕下方的應用程式與視窗在背景異步獲得焦點與啟動，消除跨螢幕焦點滯留與 macOS 背景 App Nap 滾動節流，同時絕不阻塞主執行緒即時手勢判定
    private func activateAppUnder(point: CGPoint) {
        DispatchQueue.global(qos: .userInteractive).async {
            let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
            guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }

            for window in windowList {
                guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                      let x = boundsDict["X"] as? CGFloat,
                      let y = boundsDict["Y"] as? CGFloat,
                      let w = boundsDict["Width"] as? CGFloat,
                      let h = boundsDict["Height"] as? CGFloat else { continue }

                let rect = CGRect(x: x, y: y, width: w, height: h)
                if rect.contains(point) {
                    if let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                       let app = NSRunningApplication(processIdentifier: pid),
                       app.bundleIdentifier != Bundle.main.bundleIdentifier {
                        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier == pid {
                            return
                        }
                        app.activate()
                        return
                    }
                }
            }
        }
    }

    /// 確保 WindowServer 立即更新指針全域命中測試（Hit-Testing）視窗，杜絕跨視窗與跨螢幕操作後的焦點滯留
    private func updateWindowServerPointer(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        CGWarpMouseCursorPosition(point)
        guard let moveEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        moveEvent.location = point
        moveEvent.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        moveEvent.post(tap: .cghidEventTap)
    }

    /// 發送雙向捲動事件：wheel1 為垂直 (Y)，wheel2 為水平 (X)，精確指定 location 視窗目標
    private func postScrollEvent(deltaX: CGFloat, deltaY: CGFloat, at point: CGPoint, phase: NSEvent.Phase) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        // 【換向即刻反應】：若移動方向與殘存的次像素方向相反，立即歸零殘存次像素，防止舊方向抵消反向位移
        if (deltaY > 0 && fractionalRemainderY < 0) || (deltaY < 0 && fractionalRemainderY > 0) {
            fractionalRemainderY = 0
        }
        if (deltaX > 0 && fractionalRemainderX < 0) || (deltaX < 0 && fractionalRemainderX > 0) {
            fractionalRemainderX = 0
        }

        let sign: CGFloat = naturalScroll ? 1.0 : -1.0
        let totalY = deltaY * sign * CGFloat(scrollSensitivity) + fractionalRemainderY
        let totalX = deltaX * sign * CGFloat(scrollSensitivity) + fractionalRemainderX

        fractionalRemainderY = 0
        fractionalRemainderX = 0

        if phase == .changed && abs(totalY) < 0.1 && abs(totalX) < 0.1 {
            return
        }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(round(totalY)),
            wheel2: Int32(round(totalX)),
            wheel3: 0
        ) else { return }

        // 核心關鍵 1：明確將 location 定位在落指點，WindowServer 100% 精準投遞到該視窗
        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))

        // 核心關鍵 2：直接賦予精確浮點像素值，突破 CoreGraphics 預設縮水 10 倍的限制，徹底實現 1:1 精準跟手與速度拉條完全生效！
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(totalY))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(totalX))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(round(totalY)))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(round(totalX)))

        event.post(tap: .cghidEventTap)
    }

    /// 發送雙向慣性捲動事件
    private func postMomentumScrollEvent(deltaX: CGFloat, deltaY: CGFloat, at point: CGPoint, phase: NSEvent.Phase) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(round(deltaY)),
            wheel2: Int32(round(deltaX)),
            wheel3: 0
        ) else { return }

        event.location = point
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(phase.rawValue))

        // 平滑衰減的精確浮點像素值
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(deltaY))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(deltaX))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(round(deltaY)))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(round(deltaX)))

        event.post(tap: .cghidEventTap)
    }

    /// 合成標準左鍵輕點（原子性同步發送，帶有防誤觸白名單簽名）
    private func synthesizeClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        activateAppUnder(point: point)
        updateWindowServerPointer(at: point)

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

        down.location = point
        up.location = point

        // 明確將點擊次數固定為 1，防止 macOS 連續點擊計數器判定為 Double Click / Triple Click 誤反白選取文字
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        // 設置專屬白名單簽名，確保通過 CGEventTap 攔截網
        down.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        up.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)

        down.post(tap: .cghidEventTap)

        // 給予微小且真實的點擊維持時間（約 15ms），保證瀏覽器、按鈕動畫與選單可靠捕捉 Click
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            up.post(tap: .cghidEventTap)
        }
    }

    /// 合成 Windows 風格長按右鍵選單（原子性同步發送，帶有防誤觸白名單簽名）
    private func synthesizeRightClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard isLongPressRightClickEnabled else { return }

        updateWindowServerPointer(at: point)

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

        down.location = point
        up.location = point

        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)

        down.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        up.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Dedicated Mouse Drag Actions (專用拖曳合成，無任何中斷干擾)

    /// 發送乾淨的滑鼠左鍵按下（啟動視窗或物件拖曳）
    private func postMouseDown(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        CGWarpMouseCursorPosition(point)
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.location = point
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        event.post(tap: .cghidEventTap)
    }

    /// 發送連續的滑鼠左鍵拖曳（絕不插入 mouseMoved 或 cursor warp，確保 WindowServer 拖曳不中斷）
    private func postMouseDragged(to point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDragged,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.location = point
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        event.post(tap: .cghidEventTap)
    }

    /// 發送滑鼠左鍵釋放（結束視窗或物件拖曳）
    private func postMouseUp(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.location = point
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        event.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        event.post(tap: .cghidEventTap)
    }
}
