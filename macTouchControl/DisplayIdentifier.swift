//
//  DisplayIdentifier.swift
//  macTouchControl
//

import SwiftUI
import AppKit

@MainActor
final class DisplayIdentifier {
    static let shared = DisplayIdentifier()

    private var activeWindows: [NSWindow] = []
    private var dismissTimer: Timer?

    /// 同步在所有偵測到的實體螢幕中央彈出大號標籤卡片
    func identifyAllDisplays() {
        dismissAll()
        let displays = DisplayManager.shared.displays
        for (index, display) in displays.enumerated() {
            showOverlay(for: display, displayIndex: index + 1)
        }
        scheduleDismissal()
    }

    /// 僅在特定螢幕中央彈出識別標籤卡片
    func identify(display: DisplayInfo) {
        dismissAll()
        let displays = DisplayManager.shared.displays
        let index = displays.firstIndex(where: { $0.id == display.id }) ?? 0
        showOverlay(for: display, displayIndex: index + 1)
        scheduleDismissal()
    }

    func dismissAll() {
        dismissTimer?.invalidate()
        dismissTimer = nil

        let windowsToClose = activeWindows
        activeWindows.removeAll()

        for window in windowsToClose {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.25
                window.animator().alphaValue = 0.0
            } completionHandler: {
                window.orderOut(nil)
                window.close()
            }
        }
    }

    private func showOverlay(for display: DisplayInfo, displayIndex: Int) {
        // 尋找對應的 NSScreen
        guard let screen = NSScreen.screens.first(where: { s in
            if let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
                return num == display.id
            }
            return false
        }) else { return }

        let cardWidth: CGFloat = 340
        let cardHeight: CGFloat = 190
        let originX = screen.frame.midX - (cardWidth / 2)
        let originY = screen.frame.midY - (cardHeight / 2)
        let frameRect = NSRect(x: originX, y: originY, width: cardWidth, height: cardHeight)

        let window = NSWindow(
            contentRect: frameRect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.hasShadow = true

        let mappedDeviceNames = TouchDeviceManager.shared.devices.values
            .filter { dev in
                MappingStore.shared.targetDisplay(for: dev.id, availableDisplays: DisplayManager.shared.displays)?.id == display.id
            }
            .map(\.name)

        let rootView = DisplayIdentifyOverlayView(
            displayNumber: displayIndex,
            display: display,
            mappedDeviceNames: mappedDeviceNames
        )

        let hostingView = NSHostingView(rootView: rootView)
        window.contentView = hostingView
        window.alphaValue = 0.0
        window.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            window.animator().alphaValue = 1.0
        }

        activeWindows.append(window)
    }

    private func scheduleDismissal() {
        dismissTimer?.invalidate()
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissAll()
            }
        }
    }
}

// MARK: - Display Identify Overlay Card View
struct DisplayIdentifyOverlayView: View {
    let displayNumber: Int
    let display: DisplayInfo
    let mappedDeviceNames: [String]

    var body: some View {
        let loc = LocalizationManager.shared

        VStack(spacing: 12) {
            // 上方：大號數字識別圈與螢幕類型圖示
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 3)

                    Text("\(displayNumber)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.accentColor)

                        Text(display.name)
                            .font(.system(size: 17, weight: .bold))
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Text(loc.t(.resolution(Int(display.pixelWidth), Int(display.pixelHeight))))
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if display.isMain {
                            Text(loc.t(.mainDisplayBadge))
                                .font(.system(size: 9, weight: .heavy))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .foregroundColor(.blue)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()
            }

            Divider()
                .opacity(0.4)

            // 下方：綁定設備或座標原點
            if !mappedDeviceNames.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(loc.t(.mappedDeviceList(mappedDeviceNames.joined(separator: ", "))))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.accentColor)
                        .lineLimit(1)
                    Spacer()
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(loc.t(.origin(Int(display.bounds.origin.x), Int(display.bounds.origin.y))))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
        .padding(18)
        .frame(width: 340, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.accentColor.opacity(0.35), lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
        )
    }
}
