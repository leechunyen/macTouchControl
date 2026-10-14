//
//  TouchGestureHandler.swift
//  macTouchControl
//

import Foundation
import CoreGraphics

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

/// 預留手勢處理器介面，未來在此實作：
/// 1. 雙指/單指 Scroll (滾動)
/// 2. 右側向內滑動開通知中心 (Swipe from right to open Notification Center)
/// 3. 下方向內滑動顯示 Dock (Swipe from bottom to show Dock)
final class TouchGestureHandler {
    private var touchStartSample: TouchSample?
    private var lastSample: TouchSample?

    func processTouchSample(_ sample: TouchSample) {
        switch sample.phase {
        case .began:
            touchStartSample = sample
            lastSample = sample

        case .moved:
            lastSample = sample
            // 預留：持續追蹤軌跡以判斷是否觸發邊緣滑動手勢

        case .ended:
            if let start = touchStartSample {
                evaluateGestures(from: start, to: sample)
            }
            touchStartSample = nil
            lastSample = nil

        case .cancelled:
            touchStartSample = nil
            lastSample = nil
        }
    }

    private func evaluateGestures(from start: TouchSample, to end: TouchSample) {
        let deltaX = end.normalized.x - start.normalized.x
        let deltaY = end.normalized.y - start.normalized.y
        let duration = end.timestamp - start.timestamp

        // 預留手勢邏輯判斷（未來擴充）
        _ = (deltaX, deltaY, duration)
    }
}
