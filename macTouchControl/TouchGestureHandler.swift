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
            UserDefaults.standard.synchronize()
        }
    }

    /// 自然滑動方向：內容直接跟隨手指移動方向捲動（預設開啟）
    var naturalScroll: Bool = true {
        didSet {
            UserDefaults.standard.set(naturalScroll, forKey: "macTouchControl.naturalScroll")
            UserDefaults.standard.synchronize()
        }
    }

    /// 滑動靈敏度倍率（直接作用於浮點捲動點數）
    var scrollSensitivity: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(scrollSensitivity, forKey: "macTouchControl.scrollSensitivity")
            UserDefaults.standard.synchronize()
        }
    }

    /// 是否啟用長按觸發右鍵（按著後放開為右鍵，按著移動為 click hold 拖曳，預設開啟）
    var isLongPressRightClickEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isLongPressRightClickEnabled, forKey: "macTouchControl.longPressRightClickEnabled")
            UserDefaults.standard.synchronize()
            if !isLongPressRightClickEnabled {
                cancelLongPressTimer()
            }
        }
    }

    /// 是否啟用右邊緣向內側滑開通知中心（預設開啟）
    var isRightEdgeNotificationCenterEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isRightEdgeNotificationCenterEnabled, forKey: "macTouchControl.rightEdgeNotificationCenterEnabled")
            UserDefaults.standard.synchronize()
        }
    }

    // MARK: - Internal Gesture State

    private enum GestureState {
        case idle
        /// 手指剛落下，尚未判定為點擊、滑動、長按或拖曳
        case pending(startPoint: CGPoint, startNormalized: CGPoint, targetBounds: CGRect?, startTime: TimeInterval, maxDisplacement: CGFloat, isTitleBar: Bool)
        /// 觸碰剛好用來煞停慣性滑行（碰觸煞車），抬手時嚴禁誤點擊
        case stoppingMomentum(point: CGPoint)
        /// 正在進行雙向（垂直與水平）滑動捲動
        case scrolling(lastPoint: CGPoint, velocityTracker: [(TimeInterval, CGPoint)])
        /// 定點長按已就緒（在 0.30s~0.75s 內原地放開算右鍵；手指移動轉為拖曳）
        case longPressArmed(point: CGPoint)
        /// 定點按住超過 0.75s 不放開，已進入持續 Click Hold（例如 YouTube 2x 加速、長按按鈕），直到放開
        case clickHolding(point: CGPoint)
        /// 正在進行物件或視窗拖曳（滑鼠左鍵持續按住直到放開）
        case dragging(lastPoint: CGPoint)
        /// 正在進行右側邊緣向內滑動手勢
        case edgeSwiping(startPoint: CGPoint, startNormalized: CGPoint, targetBounds: CGRect?)
        /// 邊緣手勢已觸發（如通知中心已開），直至手指抬起期間忽略後續事件
        case edgeGestureTriggered
    }

    private var gestureState: GestureState = .idle
    private var armTimer: Timer?
    private var holdTimer: Timer?
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

    /// 手指輕點與長按防抖有效位移容許範圍 (18.0pt)：適應手指指腹接觸面自然微移，杜絕誤當微小滑動
    private let tapSlopThreshold: CGFloat = 18.0

    /// 冷啟動時的滑動門檻 (14.0pt，位移超過 14pt 明顯屬於滑動意圖，立即轉入捲動並鎖定點擊，且不誤傷定點長按)
    private let initialSlopThreshold: CGFloat = 14.0

    /// 處於活躍捲動工作階段 (Scroll Session) 時的滑動門檻 (4.0pt，連續劃動起步極度跟手)
    private let activeSessionSlopThreshold: CGFloat = 4.0

    /// 取得目前手勢應採用的滑動門檻
    private var currentSlopThreshold: CGFloat {
        isScrollSessionActive ? activeSessionSlopThreshold : initialSlopThreshold
    }

    /// 輕點判定與右鍵就緒門檻（0.30 秒）：手指放開前小於 0.3s 為單擊，達標進入右鍵就緒
    private let shortTapThreshold: TimeInterval = 0.30

    /// 定點持續 Click Hold 門檻（0.75 秒）：按住超過 0.75 秒不放開自動觸發持續左鍵按住（如 YouTube 2x 加速）
    private let clickHoldThreshold: TimeInterval = 0.75

    /// 向下相容長按門檻別名
    private var longPressThreshold: TimeInterval { shortTapThreshold }

    /// 有效輕點最短時間 (5ms)，過濾極端硬體噪訊，不吞掉極快點擊
    private let minTapDuration: TimeInterval = 0.005

    /// 慣性摩擦衰減係數（0.91 提供順暢自然且及時停駐的減速體驗）
    private let friction: Double = 0.91

    /// 觸發慣性捲動的最低釋放速度 (px/s)
    private let minMomentumVelocity: Double = 80.0

    /// 慣性停止速度 (px/s，低於此速度立即發送 .end，防止微速無限漂移停不下來)
    private let stopMomentumVelocity: Double = 12.0

    /// 判定為右邊緣區域的水平正規化門檻（螢幕最右側 5% 真正邊框區，防止誤觸截斷頁面正常捲動）
    private let rightEdgeZoneRatio: CGFloat = 0.95

    /// 右側邊緣向內滑動觸發通知中心的水平位移門檻（30pt）
    private let rightEdgeSwipeDistanceThreshold: CGFloat = 30.0

    // 連續點擊追蹤（支援雙擊開啟檔案/資料夾、三擊選取段落）
    private var lastClickTime: TimeInterval = 0
    private var lastClickPoint: CGPoint = .zero
    private var currentClickCount: Int64 = 1

    /// 系統雙擊最大允許時間間隔（動態取自 macOS 系統偏好設定，並保證觸控螢幕有充裕的判定時間）
    private var doubleClickTimeWindow: TimeInterval {
        max(NSEvent.doubleClickInterval, 0.65)
    }

    /// 觸控雙擊容許的兩次落指微幅距離誤差（45pt，約 1/3 英吋，滿足人體手指在玻璃上的連續輕擊自然漂移）
    private let doubleClickMaxDistance: CGFloat = 45.0

    // 專屬事件來源，內建白名單簽名
    private let eventSource: CGEventSource? = {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = TouchGestureHandler.synthesizedEventSignature
        return source
    }()

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
            "macTouchControl.longPressRightClickEnabled": true,
            "macTouchControl.rightEdgeNotificationCenterEnabled": true
        ])

        self.isTouchScrollEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.touchScrollEnabled")
        self.naturalScroll = UserDefaults.standard.bool(forKey: "macTouchControl.naturalScroll")
        self.isLongPressRightClickEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.longPressRightClickEnabled")
        self.isRightEdgeNotificationCenterEnabled = UserDefaults.standard.bool(forKey: "macTouchControl.rightEdgeNotificationCenterEnabled")

        let savedSensitivity = UserDefaults.standard.double(forKey: "macTouchControl.scrollSensitivity")
        self.scrollSensitivity = savedSensitivity > 0 ? savedSensitivity : 1.0
    }

    // MARK: - Touch Dispatch Entry Point

    func handleTouch(
        point: CGPoint,
        normalized: CGPoint,
        targetBounds: CGRect? = nil,
        isDown: Bool,
        tipChanged: Bool
    ) {
        let now = ProcessInfo.processInfo.systemUptime

        if tipChanged {
            if isDown {
                handleTouchDown(point: point, normalized: normalized, targetBounds: targetBounds, timestamp: now)
            } else {
                handleTouchUp(point: point, timestamp: now)
            }
        } else if isDown {
            handleTouchMoved(point: point, timestamp: now)
        }
    }

    // MARK: - Private Gesture Handlers

    private func handleTouchDown(
        point: CGPoint,
        normalized: CGPoint,
        targetBounds: CGRect? = nil,
        timestamp: TimeInterval
    ) {
        cancelLongPressTimer()

        // 判定是否正處於連續雙擊判定視窗內（使用者正在快速連點第二下）
        let isPotentialConsecutiveTap = (timestamp - lastClickTime < doubleClickTimeWindow) &&
                                        (hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y) < doubleClickMaxDistance)

        if !isPotentialConsecutiveTap {
            // 非雙擊時，背景啟動落指位置下方的應用程式以確保焦點
            activateAppUnder(point: point)
            updateWindowServerPointer(at: point)
        } else {
            // 連擊狀態下直接將游標無延遲釘死在原始點擊點，杜絕像素偏移導致 Finder 誤判
            CGWarpMouseCursorPosition(lastClickPoint)
        }
        lastScrollPoint = point

        // 檢查是否處於慣性滑行中
        let wasMomentumActive = (momentumTimer != nil)
        stopMomentum() // 發送 phase: .ended 確保系統即刻煞車，不與後續反向滑動衝突

        hasScrolledInCurrentGesture = false
        fractionalRemainderX = 0
        fractionalRemainderY = 0

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
            targetBounds: targetBounds,
            startTime: timestamp,
            maxDisplacement: 0,
            isTitleBar: onTitleBar
        )

        cancelAllTimers()

        // 【階梯 1】：0.30 秒進入右鍵就緒（若在 0.30~0.75 秒內原地放開算右鍵）
        let t1 = Timer.scheduledTimer(withTimeInterval: shortTapThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }
            if case .pending(let startPoint, _, _, _, let maxDisp, _) = self.gestureState {
                if maxDisp < self.tapSlopThreshold {
                    self.gestureState = .longPressArmed(point: startPoint)
                }
            }
        }
        RunLoop.main.add(t1, forMode: .common)
        self.armTimer = t1

        // 【階梯 2】：0.75 秒按著不放開，觸發持續 Click Hold 直到放開（例如 YouTube 2x 加速）
        let t2 = Timer.scheduledTimer(withTimeInterval: clickHoldThreshold, repeats: false) { [weak self] _ in
            guard let self else { return }
            switch self.gestureState {
            case .pending(let startPoint, _, _, _, let maxDisp, _):
                if maxDisp < self.tapSlopThreshold {
                    self.gestureState = .clickHolding(point: startPoint)
                    self.postMouseDown(at: startPoint)
                }
            case .longPressArmed(let startPoint):
                // 使用者按住超過 0.75 秒不放開：轉入持續 Click Hold！
                self.gestureState = .clickHolding(point: startPoint)
                self.postMouseDown(at: startPoint)
            default:
                break
            }
        }
        RunLoop.main.add(t2, forMode: .common)
        self.holdTimer = t2
    }

    private func handleTouchMoved(point: CGPoint, timestamp: TimeInterval) {
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

        case .pending(let startPoint, let startNorm, let targetBounds, let startTime, let maxDisp, let isTitleBar):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)
            let updatedMaxDisp = max(maxDisp, distance)

            // 連擊防抖保護：若處於連續雙擊判定視窗內（使用者正在快速連點第二下），放寬門檻（22.0pt）
            // 杜絕手指快速連擊時因著力面積微移被誤判為微小拖曳或捲動！
            let isPotentialConsecutiveTap = (timestamp - lastClickTime < doubleClickTimeWindow) &&
                                            (hypot(startPoint.x - lastClickPoint.x, startPoint.y - lastClickPoint.y) < doubleClickMaxDistance)
            let threshold = isPotentialConsecutiveTap ? 22.0 : currentSlopThreshold

            if distance >= threshold {
                cancelLongPressTimer()

                // 【右側邊緣向內滑開通知中心】：觸碰起始於螢幕最右側（norm.x >= 0.85）且向左滑動
                if isRightEdgeNotificationCenterEnabled && startNorm.x >= rightEdgeZoneRatio && dx < 0 && -dx > abs(dy) * 0.5 {
                    if -dx >= rightEdgeSwipeDistanceThreshold {
                        hasScrolledInCurrentGesture = true
                        gestureState = .edgeGestureTriggered
                        SystemGestureService.toggleNotificationCenter(on: targetBounds, returnCursorTo: point)
                    } else {
                        gestureState = .edgeSwiping(startPoint: startPoint, startNormalized: startNorm, targetBounds: targetBounds)
                    }
                    return
                }

                if isTitleBar || !isTouchScrollEnabled {
                    // 【視窗標題列直接拖曳，或關閉平板捲動時的標準滑鼠拖曳模式】：
                    // 手指滑動直接進行視窗或物件拖曳！
                    gestureState = .dragging(lastPoint: point)
                    postMouseDown(at: startPoint)
                    postMouseDragged(to: point)
                } else {
                    // 【平板雙向捲動模式】：超過門檻，無延遲切入雙向平板滑動捲動模式
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
                    targetBounds: targetBounds,
                    startTime: startTime,
                    maxDisplacement: updatedMaxDisp,
                    isTitleBar: isTitleBar
                )
            }

        case .edgeSwiping(let startPoint, let startNorm, let targetBounds):
            let inward = startPoint.x - point.x
            let dy = point.y - startPoint.y

            if inward >= rightEdgeSwipeDistanceThreshold {
                hasScrolledInCurrentGesture = true
                gestureState = .edgeGestureTriggered
                SystemGestureService.toggleNotificationCenter(on: targetBounds, returnCursorTo: point)
            } else if inward < -15 || abs(dy) > max(35.0, inward * 1.8) {
                // 使用者明顯轉為垂直滾動或往外滑出，無縫退回標準雙向滾動
                hasScrolledInCurrentGesture = true
                lastScrollTimestamp = timestamp
                lastScrollPoint = point
                gestureState = .scrolling(lastPoint: point, velocityTracker: [(timestamp, point)])
                postScrollEvent(deltaX: point.x - startPoint.x, deltaY: dy, at: point, phase: .began)
            }

        case .edgeGestureTriggered:
            // 手勢已觸發，等待抬手，不合成任何位移
            break

        case .longPressArmed(let startPoint):
            let dx = point.x - startPoint.x
            let dy = point.y - startPoint.y
            let distance = hypot(dx, dy)

            if distance >= initialSlopThreshold {
                // 【按著後手指移動】：取消 0.75s 計時器，直接進入拖曳模式直到放開！
                cancelHoldTimer()
                gestureState = .dragging(lastPoint: point)
                postMouseDown(at: startPoint)
                postMouseDragged(to: point)
            }

        case .clickHolding(let lastPoint):
            let dx = point.x - lastPoint.x
            let dy = point.y - lastPoint.y
            if hypot(dx, dy) >= 2.0 {
                gestureState = .clickHolding(point: point)
                postMouseDragged(to: point)
            }

        case .dragging:
            // 正在進行拖曳，發送連續專用左鍵拖曳事件
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

        switch gestureState {
        case .idle:
            break

        case .stoppingMomentum:
            gestureState = .idle
            lastScrollTimestamp = timestamp
            // 煞車手勢抬起，絕對不觸發任何點擊

        case .edgeSwiping:
            // 未達滑動觸發門檻即抬起，重設為 idle，不觸發誤點擊
            gestureState = .idle

        case .edgeGestureTriggered:
            // 手勢完成抬手，重設為 idle
            gestureState = .idle

        case .pending(let startPoint, _, _, let startTime, let maxDisp, _):
            gestureState = .idle
            let elapsed = timestamp - startTime
            let liftDist = hypot(point.x - startPoint.x, point.y - startPoint.y)

            // 連擊防抖保護：若處於連續雙擊判定視窗內，適度放寬指腹容許範圍
            let isPotentialConsecutiveTap = (timestamp - lastClickTime < doubleClickTimeWindow) &&
                                            (hypot(startPoint.x - lastClickPoint.x, startPoint.y - lastClickPoint.y) < doubleClickMaxDistance)
            let allowedSlop = isPotentialConsecutiveTap ? 25.0 : tapSlopThreshold

            if !hasScrolledInCurrentGesture &&
               elapsed >= minTapDuration &&
               elapsed < longPressThreshold &&
               liftDist < allowedSlop &&
               maxDisp < allowedSlop {
                synthesizeClick(at: startPoint)
            }

        case .longPressArmed(let startPoint):
            cancelAllTimers()
            gestureState = .idle
            // 【按著後放開算右鍵】：在 0.30s~0.75s 之間原地放開手指，觸發右鍵快捷選單！
            if isLongPressRightClickEnabled {
                synthesizeRightClick(at: startPoint)
            } else {
                synthesizeClick(at: startPoint)
            }

        case .clickHolding(let pt):
            // 【按著不放開算 click hold 直到放開】：按住超過 0.75s 放開（例如 YouTube 加速放開結束）
            cancelAllTimers()
            gestureState = .idle
            postMouseUp(at: pt)
            WindowFrameCache.shared.refreshAsync()

        case .dragging:
            // 拖曳結束放開
            cancelAllTimers()
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

    private func cancelAllTimers() {
        armTimer?.invalidate()
        armTimer = nil
        holdTimer?.invalidate()
        holdTimer = nil
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    private func cancelHoldTimer() {
        holdTimer?.invalidate()
        holdTimer = nil
    }

    private func cancelLongPressTimer() {
        cancelAllTimers()
    }

    // MARK: - 2D Momentum Simulation (支援垂直與水平雙向慣性捲動)

    private func startMomentum(vx: Double, vy: Double, at point: CGPoint) {
        stopMomentum()
        lastScrollPoint = point
        let sign: Double = naturalScroll ? 1.0 : -1.0
        momentumVx = vx * sign * scrollSensitivity
        momentumVy = vy * sign * scrollSensitivity

        postMomentumScrollEvent(deltaX: 0, deltaY: 0, at: point, phase: .begin)

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
            postMomentumScrollEvent(deltaX: CGFloat(stepX), deltaY: CGFloat(stepY), at: lastScrollPoint, phase: .continuous)
        }
    }

    private func stopMomentum() {
        if momentumTimer != nil {
            momentumTimer?.invalidate()
            momentumTimer = nil
            momentumVx = 0
            momentumVy = 0
            lastScrollTimestamp = ProcessInfo.processInfo.systemUptime
            // 發送 phase: .end 立即通知 macOS 系統終止慣性滑行，不延遲後續反向滑動
            postMomentumScrollEvent(deltaX: 0, deltaY: 0, at: lastScrollPoint, phase: .end)
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

    /// 確保 WindowServer 立即更新游標位置，杜絕跨視窗與跨螢幕操作後的焦點滯留
    private func updateWindowServerPointer(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        CGWarpMouseCursorPosition(point)
    }

    /// 發送雙向捲動事件：wheel1 為垂直 (Y)，wheel2 為水平 (X)，精確指定 location 視窗目標
    private func postScrollEvent(deltaX: CGFloat, deltaY: CGFloat, at point: CGPoint, phase: CGScrollPhase) {
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
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(CGMomentumScrollPhase.none.rawValue))

        // 核心關鍵 2：直接賦予精確浮點像素值，突破 CoreGraphics 預設縮水 10 倍的限制，徹底實現 1:1 精準跟手與速度拉條完全生效！
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(totalY))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(totalX))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(round(totalY)))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(round(totalX)))

        event.post(tap: .cghidEventTap)
    }

    /// 發送雙向慣性捲動事件
    private func postMomentumScrollEvent(deltaX: CGFloat, deltaY: CGFloat, at point: CGPoint, phase: CGMomentumScrollPhase) {
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
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(phase.rawValue))

        // 平滑衰減的精確浮點像素值
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(deltaY))
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(deltaX))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(round(deltaY)))
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(round(deltaX)))

        event.post(tap: .cghidEventTap)
    }

    /// 合成標準左鍵輕點（原生連擊判定、座標精準鎖定、白名單簽名、HID 硬體級可靠派發）
    private func synthesizeClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        let now = ProcessInfo.processInfo.systemUptime
        let clickInterval = now - lastClickTime
        let clickDist = hypot(point.x - lastClickPoint.x, point.y - lastClickPoint.y)

        // 判定是否為連續點擊（雙擊或三擊）
        let isConsecutive = (clickInterval < doubleClickTimeWindow) && (clickDist < doubleClickMaxDistance)

        let clickPoint: CGPoint
        if isConsecutive {
            currentClickCount = min(currentClickCount + 1, 3)
            // 【核心修正】：連續點擊時，將座標 100% 釘死在第一次點擊的原始座標！
            // 解決 Finder 判定 4px 偏移導致視為單擊選取/重新命名檔案的問題，確保 Finder 百分之百觸發雙擊開啟檔案！
            clickPoint = lastClickPoint
        } else {
            currentClickCount = 1
            clickPoint = point
            lastClickPoint = point
        }
        lastClickTime = now

        // 游標即刻對齊目標座標（絕不發送 mouseMoved 避免重置 AppKit clickCount）
        CGWarpMouseCursorPosition(clickPoint)

        guard let down = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseDown,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .leftMouseUp,
            mouseCursorPosition: clickPoint,
            mouseButton: .left
        ) else { return }

        down.location = clickPoint
        up.location = clickPoint

        down.setIntegerValueField(.mouseEventClickState, value: currentClickCount)
        up.setIntegerValueField(.mouseEventClickState, value: currentClickCount)

        // 設置專屬白名單簽名，確保通過 CGEventTap 攔截網
        down.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)
        up.setIntegerValueField(.eventSourceUserData, value: Self.synthesizedEventSignature)

        // 派發至 .cghidEventTap（硬體級事件隊列，Finder、Dock 與沙盒應用完全信賴並支援 Double Click 啟動）
        down.post(tap: .cghidEventTap)
        usleep(12_000) // 12ms 原子性脈衝，確保按鍵狀態可靠傳遞且不與下次點擊競爭
        up.post(tap: .cghidEventTap)
    }

    /// 合成 Windows 風格長按右鍵選單（原子性同步發送，帶有防誤觸白名單簽名）
    private func synthesizeRightClick(at point: CGPoint) {
        guard PermissionManager.shared.isAccessibilityGranted else { return }
        guard isLongPressRightClickEnabled else { return }

        updateWindowServerPointer(at: point)

        guard let down = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .rightMouseDown,
            mouseCursorPosition: point,
            mouseButton: .right
        ),
        let up = CGEvent(
            mouseEventSource: eventSource,
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
            mouseEventSource: eventSource,
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
            mouseEventSource: eventSource,
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
            mouseEventSource: eventSource,
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
