//
//  LongPressRingOverlay.swift
//  macTouchControl
//

import AppKit
import SwiftUI
import Combine

/// 倒數光圈動畫狀態模型
final class LongPressRingModel: ObservableObject {
    @Published var progress: CGFloat = 0.0
    @Published var isVisible: Bool = false
    @Published var isCompleted: Bool = false
}

/// 倒數光圈 SwiftUI 視圖（加大環形進度條，外擴於手指輪廓外清晰可見）
struct LongPressRingView: View {
    @ObservedObject var model: LongPressRingModel

    var body: some View {
        ZStack {
            if model.isVisible {
                // 底圈（柔和半透明背景，擴大至 84pt 確保手指不遮擋）
                Circle()
                    .stroke(Color.white.opacity(0.35), lineWidth: 4.5)
                    .background(Circle().fill(Color.black.opacity(0.20)))

                // 動畫進度條（隨時間流暢填滿）
                Circle()
                    .trim(from: 0.0, to: model.progress)
                    .stroke(
                        model.isCompleted ? Color.green : Color.accentColor,
                        style: StrokeStyle(lineWidth: 5.0, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // 中心微光反饋點
                Circle()
                    .fill(model.isCompleted ? Color.green : Color.accentColor)
                    .frame(width: model.isCompleted ? 12 : 8, height: model.isCompleted ? 12 : 8)
            }
        }
        .frame(width: 84, height: 84)
        .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
    }
}

/// 長按倒數光圈浮動視窗控制器
@MainActor
final class LongPressRingOverlay {
    static let shared = LongPressRingOverlay()

    private var panel: NSPanel?
    private let model = LongPressRingModel()
    private var animationTimer: Timer?
    /// 光圈視窗大小（92pt，提供足夠空間完整顯示 84pt 光圈與陰影）
    private let ringSize: CGFloat = 92.0

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: ringSize, height: ringSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .popUpMenu // 浮在一般視窗與全螢幕 App 之上
        p.ignoresMouseEvents = true // 絕不阻擋任何觸控與滑鼠點擊事件
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let hostingView = NSHostingView(rootView: LongPressRingView(model: model))
        p.contentView = hostingView
        self.panel = p
    }

    /// 在指定螢幕座標展示倒數光圈並開始計時動畫
    func show(at globalPoint: CGPoint, duration: TimeInterval) {
        animationTimer?.invalidate()
        animationTimer = nil

        guard let panel = self.panel else { return }

        // 轉換全域座標 (CGEvent Top-Left 轉 AppKit Bottom-Left)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        let originX = globalPoint.x - (ringSize / 2.0)
        let originY = primaryHeight - globalPoint.y - (ringSize / 2.0)

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.orderFrontRegardless()

        model.progress = 0.0
        model.isCompleted = false
        model.isVisible = true

        let startTime = ProcessInfo.processInfo.systemUptime
        let interval: TimeInterval = 0.016 // ~60fps
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] t in
            guard let self = self else {
                t.invalidate()
                return
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - startTime
            let pct = min(CGFloat(elapsed / duration), 1.0)
            self.model.progress = pct

            if pct >= 1.0 {
                t.invalidate()
                self.animationTimer = nil
                self.model.isCompleted = true
                // 停留極短暫脈衝後淡出
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if self.model.isCompleted {
                        self.hide()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.animationTimer = timer
    }

    /// 隱藏光圈
    func hide() {
        animationTimer?.invalidate()
        animationTimer = nil
        model.isVisible = false
        model.progress = 0.0
        model.isCompleted = false
        panel?.orderOut(nil)
    }
}
