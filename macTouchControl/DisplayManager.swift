//
//  DisplayManager.swift
//  macTouchControl
//

import SwiftUI
import AppKit
import CoreGraphics
import Observation

struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let name: String
    let bounds: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    let isMain: Bool
    let isBuiltin: Bool
    let isMirror: Bool

    func displayNameWithDetails(loc: LocalizationManager = .shared) -> String {
        let mainTag = isMain ? loc.t(.mainDisplayTag) : ""
        let mirrorTag = isMirror ? loc.t(.mirrorDisplayTag) : ""
        return "\(name) (\(pixelWidth)×\(pixelHeight))\(mainTag)\(mirrorTag)"
    }
}

@Observable
@MainActor
final class DisplayManager {
    static let shared = DisplayManager()

    var displays: [DisplayInfo] = []
    var isMirroringActive: Bool = false

    nonisolated(unsafe) private var screenObserver: Any?

    init() {
        refreshDisplays()
        setupNotificationObserver()
    }

    deinit {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func refreshDisplays() {
        var activeDisplayCount: UInt32 = 0
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        let error = CGGetActiveDisplayList(16, &displayIDs, &activeDisplayCount)

        guard error == .success else {
            return
        }

        var detectedDisplays: [DisplayInfo] = []
        var anyMirror = false

        for i in 0..<Int(activeDisplayCount) {
            let displayID = displayIDs[i]
            let bounds = CGDisplayBounds(displayID)
            let isMain = CGDisplayIsMain(displayID) != 0
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let isMirror = CGDisplayIsInMirrorSet(displayID) != 0

            if isMirror {
                anyMirror = true
            }

            // 尋找對應的 NSScreen 取得螢幕名稱與真實像素尺寸
            let loc = LocalizationManager.shared
            var screenName = isBuiltin ? loc.t(.builtinDisplay) : loc.t(.externalDisplay(displayID))
            var pixelWidth = Int(bounds.width)
            var pixelHeight = Int(bounds.height)

            for screen in NSScreen.screens {
                if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                   screenNumber == displayID {
                    screenName = screen.localizedName
                    let backingSize = screen.convertRectToBacking(screen.frame).size
                    pixelWidth = Int(backingSize.width)
                    pixelHeight = Int(backingSize.height)
                    break
                }
            }

            let info = DisplayInfo(
                id: displayID,
                name: screenName,
                bounds: bounds,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                isMain: isMain,
                isBuiltin: isBuiltin,
                isMirror: isMirror
            )
            detectedDisplays.append(info)
        }

        self.displays = detectedDisplays
        self.isMirroringActive = anyMirror
    }

    func display(for id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    var mainDisplay: DisplayInfo? {
        displays.first { $0.isMain } ?? displays.first
    }

    private func setupNotificationObserver() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshDisplays()
            }
        }
    }
}
