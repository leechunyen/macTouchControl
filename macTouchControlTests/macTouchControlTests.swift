//
//  macTouchControlTests.swift
//  macTouchControlTests
//
//  Created by LeeChunYen on 14/10/2026.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import macTouchControl

struct MacTouchControlTests {

    @Test("測試語言自動檢測與Fallback機制")
    func testLanguageDetectionAndFallback() {
        // 1. 繁體中文偏好 -> 解析為 zh_tw
        let zhTW = LocalizationManager.resolveLanguage(from: ["zh-TW", "en-US"])
        #expect(zhTW == .zh_tw)

        let zhHant = LocalizationManager.resolveLanguage(from: ["zh-Hant-HK", "en"])
        #expect(zhHant == .zh_tw)

        // 2. 英文偏好 -> 解析為 en_us
        let en = LocalizationManager.resolveLanguage(from: ["en-US", "zh-TW"])
        #expect(en == .en_us)

        // 3. 其他非中英語系（例如日文、法文） -> 自動 Fallback 到 en_us
        let japaneseFallback = LocalizationManager.resolveLanguage(from: ["ja-JP", "fr-FR"])
        #expect(japaneseFallback == .en_us)

        let germanFallback = LocalizationManager.resolveLanguage(from: ["de-DE"])
        #expect(germanFallback == .en_us)

        // 4. 空列表 -> Fallback 到 en_us
        let emptyFallback = LocalizationManager.resolveLanguage(from: [])
        #expect(emptyFallback == .en_us)
    }

    @Test("測試動態語系切換與嚴格台灣繁體中文用語")
    @MainActor
    func testLocalizedStrings() {
        // 使用隔離的測試 suite，避免覆寫或清空使用者實際的 UserDefaults 設定
        let testSuiteName = "macTouchControl.test.\(UUID().uuidString)"
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        defer {
            testDefaults.removePersistentDomain(forName: testSuiteName)
        }

        // 驗證相容性解析
        #expect(AppLanguage.from(string: "zh_tw") == .zh_tw)
        #expect(AppLanguage.from(string: "zh-Hant") == .zh_tw)
        #expect(AppLanguage.from(string: "en_us") == .en_us)
        #expect(AppLanguage.from(string: "system") == .system)

        let freshManager = LocalizationManager(defaults: testDefaults)
        #expect(freshManager.selectedLanguage == .system)
        #expect(AppLanguage.system.displayName == "System")
        #expect(AppLanguage.en_us.displayName == "English (US)")
        #expect(AppLanguage.zh_tw.displayName == "繁體中文 (台灣)")

        // 測試持久化保存 user setting
        freshManager.selectedLanguage = .system
        #expect(testDefaults.string(forKey: "macTouchControl.appLanguage") == "system")
        #expect(testDefaults.string(forKey: "macTouchControl.language") == "system")

        freshManager.selectedLanguage = .zh_tw
        #expect(testDefaults.string(forKey: "macTouchControl.appLanguage") == "zh-Hant")
        #expect(testDefaults.string(forKey: "macTouchControl.language") == "zh-Hant")

        let manager = LocalizationManager(defaults: testDefaults)

        // 強制切換為英文
        manager.selectedLanguage = .en_us
        #expect(manager.t(.appSubtitle) == "Touchscreen Utility")
        #expect(manager.t(.disconnectedDisplay) == "Disconnected")
        #expect(manager.t(.statusActive) == "Service Active")
        #expect(manager.t(.mappingSectionTitle) == "Touch Panel & Display 1-to-1 Mapping")
        #expect(manager.t(.accessibilityTitle) == "Accessibility")
        #expect(manager.t(.mainDisplayBadge) == "Main")
        #expect(manager.t(.gestureScrollTitle) == "Touchscreen 2D Scrolling (Tablet Mode)")
        #expect(manager.t(.longPressRightClickTitle) == "Long Press for Right-Click (Windows Style)")
        #expect(manager.t(.menuToggleLongPressRightClick) == "Long Press for Right-Click (Windows Style)")
        #expect(manager.t(.identifyDisplaysButton) == "Identify")

        // 強制切換為繁體中文（嚴格台灣用語：裝置、螢幕、捲動、預設）
        manager.selectedLanguage = .zh_tw
        #expect(manager.t(.appSubtitle) == "觸控螢幕工具")
        #expect(manager.t(.disconnectedDisplay) == "已中斷連線")
        #expect(manager.t(.statusActive) == "服務運作中")
        #expect(manager.t(.identifyDisplaysButton) == "識別螢幕")
        #expect(manager.t(.mappingSectionTitle) == "觸控面板與螢幕 1 對 1 綁定")
        #expect(manager.t(.rescanButton) == "重新掃描裝置")
        #expect(manager.t(.defaultTouchDeviceName) == "觸控裝置")
        #expect(manager.t(.accessibilityTitle) == "輔助使用 (Accessibility)")
        #expect(manager.t(.mainDisplayBadge) == "主螢幕")
        #expect(manager.t(.gestureScrollTitle) == "觸控螢幕雙向捲動 (平板 / 手機模式)")
        #expect(manager.t(.naturalScrollTitle) == "自然捲動方向 (Natural Scrolling)")
        #expect(manager.t(.longPressRightClickTitle) == "長按觸發右鍵 (如同 Windows 觸控體驗)")
        #expect(manager.t(.menuToggleLongPressRightClick) == "長按觸發右鍵選單 (Windows 風格)")
    }

    @Test("測試觸控設備座標標準化與邊界約束")
    func testCoordinateNormalization() {
        let device = TouchDevice(
            id: "test_dev_1",
            name: "Test Touch Panel",
            minX: 0,
            maxX: 1000,
            minY: 0,
            maxY: 2000
        )

        let center = device.normalizedCoordinate(rawX: 500, rawY: 1000)
        #expect(center.x == 0.5)
        #expect(center.y == 0.5)

        let origin = device.normalizedCoordinate(rawX: 0, rawY: 0)
        #expect(origin.x == 0.0)
        #expect(origin.y == 0.0)

        let maxPoint = device.normalizedCoordinate(rawX: 1000, rawY: 2000)
        #expect(maxPoint.x == 1.0)
        #expect(maxPoint.y == 1.0)

        // 測試超出邊界的 clamp
        let clampedLow = device.normalizedCoordinate(rawX: -100, rawY: -50)
        #expect(clampedLow.x == 0.0)
        #expect(clampedLow.y == 0.0)

        let clampedHigh = device.normalizedCoordinate(rawX: 2000, rawY: 4000)
        #expect(clampedHigh.x == 1.0)
        #expect(clampedHigh.y == 1.0)
    }

    @Test("測試螢幕綁定與動態匹配儲存")
    @MainActor
    func testDeviceMappingStore() {
        let store = MappingStore()
        let display = DisplayInfo(
            id: 101,
            name: "外接觸控螢幕 A",
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            pixelWidth: 1920,
            pixelHeight: 1080,
            isMain: false,
            isBuiltin: false,
            isMirror: false
        )

        store.bind(deviceID: "dev_touch_1", deviceName: "Touch Panel 1", display: display)

        // 測試精準 ID 匹配
        let matched = store.targetDisplay(for: "dev_touch_1", availableDisplays: [display])
        #expect(matched?.id == 101)
        #expect(matched?.name == "外接觸控螢幕 A")

        // 測試螢幕拔掉時：儲存的映射設定保持不被清除，僅回傳 nil
        #expect(store.targetDisplay(for: "dev_touch_1", availableDisplays: []) == nil)
        #expect(store.mappings["dev_touch_1"] != nil)
        #expect(store.mappings["dev_touch_1"]?.targetDisplayName == "外接觸控螢幕 A")

        // 測試螢幕重新連線後 DisplayID 變更但名稱相符的模糊修復匹配
        let reconnectedDisplay = DisplayInfo(
            id: 202,
            name: "  外接觸控螢幕 A  ",
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            pixelWidth: 1920,
            pixelHeight: 1080,
            isMain: false,
            isBuiltin: false,
            isMirror: false
        )
        let fallbackMatched = store.targetDisplay(for: "dev_touch_1", availableDisplays: [reconnectedDisplay])
        #expect(fallbackMatched?.id == 202)
        #expect(store.mappings["dev_touch_1"]?.targetDisplayID == 202)

        // 測試解除綁定
        store.unbind(deviceID: "dev_touch_1")
        #expect(store.targetDisplay(for: "dev_touch_1", availableDisplays: [reconnectedDisplay]) == nil)
    }

    @Test("測試排除Mac內建鍵盤觸控板與非觸控設備")
    func testIneligibleDeviceFiltering() {
        // 1. Apple 內建鍵盤與觸控板 -> 必須排除 (false)
        let appleInternal = TouchDeviceManager.isEligibleTouchDevice(
            name: "Apple Internal Keyboard / Trackpad",
            manufacturer: "Apple",
            vendorID: 0x05AC,
            isBuiltIn: true
        )
        #expect(appleInternal == false)

        // 2. Apple Magic Trackpad / Mouse -> 必須排除 (false)
        let magicTrackpad = TouchDeviceManager.isEligibleTouchDevice(
            name: "Magic Trackpad",
            manufacturer: "Apple Inc.",
            vendorID: 0x05AC,
            isBuiltIn: false
        )
        #expect(magicTrackpad == false)

        // 3. 常規 USB 滑鼠 -> 必須排除 (false)
        let standardMouse = TouchDeviceManager.isEligibleTouchDevice(
            name: "USB Optical Mouse",
            manufacturer: "Logitech",
            vendorID: 0x046D,
            isBuiltIn: false
        )
        #expect(standardMouse == false)

        // 4. 外接觸控螢幕 (例如 ACDC Touch Input Device) -> 必須保留 (true)
        let acdcTouch = TouchDeviceManager.isEligibleTouchDevice(
            name: "ACDC Touch Input Device",
            manufacturer: "ACDC Co.,Ltd.",
            vendorID: 0x2A94,
            isBuiltIn: false
        )
        #expect(acdcTouch == true)

        // 5. 外接觸控螢幕 (例如 ASUS ZenScreen Touch) -> 必須保留 (true)
        let asusTouch = TouchDeviceManager.isEligibleTouchDevice(
            name: "ASUS ZenScreen Touch MB16AMT",
            manufacturer: "ASUSTeK Computer Inc.",
            vendorID: 0x0B05,
            isBuiltIn: false
        )
        #expect(asusTouch == true)
    }

    @Test("測試平板觸控滑動手勢處理器預設值、雙向跟手、換向即刻反應與Click鎖定")
    @MainActor
    func testTouchGestureHandlerCycle() {
        // 先清除持久化快取，以驗證乾淨環境下的預設值
        UserDefaults.standard.removeObject(forKey: "macTouchControl.touchScrollEnabled")
        UserDefaults.standard.removeObject(forKey: "macTouchControl.naturalScroll")
        UserDefaults.standard.removeObject(forKey: "macTouchControl.scrollSensitivity")
        UserDefaults.standard.removeObject(forKey: "macTouchControl.longPressRightClickEnabled")

        let handler = TouchGestureHandler()

        // 驗證核心預設值：平板滑動體驗、自然滑動方向、長按觸發右鍵預設必須開啟
        #expect(handler.isTouchScrollEnabled == true)
        #expect(handler.naturalScroll == true)
        #expect(handler.scrollSensitivity == 1.0)
        #expect(handler.isLongPressRightClickEnabled == true)

        // 測試使用者自訂開關長按右鍵功能
        handler.isLongPressRightClickEnabled = false
        #expect(handler.isLongPressRightClickEnabled == false)
        #expect(UserDefaults.standard.bool(forKey: "macTouchControl.longPressRightClickEnabled") == false)

        handler.isLongPressRightClickEnabled = true
        #expect(handler.isLongPressRightClickEnabled == true)
        #expect(UserDefaults.standard.bool(forKey: "macTouchControl.longPressRightClickEnabled") == true)

        let tapPoint = CGPoint(x: 200, y: 300)
        let norm = CGPoint(x: 0.2, y: 0.3)

        // 模擬正常輕點 Tap（在非捲動冷卻期間快速點擊釋放）
        handler.handleTouch(point: tapPoint, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: tapPoint, normalized: norm, isDown: false, tipChanged: true)

        // 模擬極致跟手的滑動循環（支援橫向與上下捲動）
        let scrollStart = CGPoint(x: 300, y: 400)
        handler.handleTouch(point: scrollStart, normalized: norm, isDown: true, tipChanged: true)

        // 移動超過 3.5 點閥值立即觸發雙向跟手捲動，並進入 Click 鎖定
        let scrollMove1 = CGPoint(x: 330, y: 440)
        handler.handleTouch(point: scrollMove1, normalized: norm, isDown: true, tipChanged: false)
        #expect(handler.hasScrolledInCurrentGesture == true)
        #expect(handler.isScrollSessionActive == true)

        // 測試突然急遽反轉換向：從 (+30, +40) 突然往反方向 (-50, -60) 移動
        let reverseMove = CGPoint(x: 280, y: 380)
        handler.handleTouch(point: reverseMove, normalized: norm, isDown: true, tipChanged: false)
        #expect(handler.hasScrolledInCurrentGesture == true)

        // 釋放手勢：由於處於 scrolling 狀態，絕對鎖死 Click，不觸發任何誤點擊
        handler.handleTouch(point: reverseMove, normalized: norm, isDown: false, tipChanged: true)
        #expect(handler.isScrollSessionActive == true)

        // 測試在捲動工作階段內（滑動剛結束 400ms 內）的碰觸煞車與防誤點擊：
        // 觸碰落指並迅速抬起，因處於 isScrollSessionActive，Click 依然處於鎖定保護狀態
        let brakePoint = CGPoint(x: 280, y: 380)
        handler.handleTouch(point: brakePoint, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: brakePoint, normalized: norm, isDown: false, tipChanged: true)

        // 測試修改配置後，能重設回預設值
        handler.naturalScroll = false
        #expect(handler.naturalScroll == false)

        handler.scrollSensitivity = 1.5
        #expect(handler.scrollSensitivity == 1.5)

        handler.isTouchScrollEnabled = false
        #expect(handler.isTouchScrollEnabled == false)

        // 重設回預設值
        handler.isTouchScrollEnabled = true
        handler.naturalScroll = true
        handler.scrollSensitivity = 1.0
        handler.isLongPressRightClickEnabled = true
    }

    @Test("測試關閉長按右鍵時的狀態與靈敏度調節")
    @MainActor
    func testDisabledRightClickAndSensitivityRange() {
        let handler = TouchGestureHandler()
        handler.isLongPressRightClickEnabled = false
        #expect(handler.isLongPressRightClickEnabled == false)

        handler.scrollSensitivity = 2.5
        #expect(handler.scrollSensitivity == 2.5)
        #expect(UserDefaults.standard.double(forKey: "macTouchControl.scrollSensitivity") == 2.5)

        let holdPoint = CGPoint(x: 200, y: 200)
        let norm = CGPoint(x: 0.2, y: 0.2)
        handler.handleTouch(point: holdPoint, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: holdPoint, normalized: norm, isDown: false, tipChanged: true)

        // 復原預設
        handler.scrollSensitivity = 1.0
        handler.isLongPressRightClickEnabled = true
    }

    @Test("測試視窗拖曳與按著拖手勢模擬")
    @MainActor
    func testWindowDraggingAndPressHoldDrag() {
        let handler = TouchGestureHandler()
        let norm = CGPoint(x: 0.5, y: 0.5)

        // 1. 模擬快速滑動（捲動）
        let startPt = CGPoint(x: 300, y: 500)
        let movePt = CGPoint(x: 300, y: 560)
        handler.handleTouch(point: startPt, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: movePt, normalized: norm, isDown: true, tipChanged: false)
        #expect(handler.hasScrolledInCurrentGesture == true)
        handler.handleTouch(point: movePt, normalized: norm, isDown: false, tipChanged: true)

        // 2. 模擬普通點擊
        let tapPt = CGPoint(x: 400, y: 400)
        handler.handleTouch(point: tapPt, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: tapPt, normalized: norm, isDown: false, tipChanged: true)
    }

    @Test("測試開機自動啟動管理器與本地化字串")
    @MainActor
    func testAutoStartManagerAndLifecycle() {
        let autoStart = AutoStartManager.shared
        autoStart.checkStatus()
        autoStart.evaluateLaunchTrigger()

        // 驗證本地化字串（測試完成後自動還原 shared 語言）
        let loc = LocalizationManager.shared
        let originalLang = loc.selectedLanguage
        defer {
            loc.selectedLanguage = originalLang
        }
        loc.selectedLanguage = .en_us
        #expect(loc.t(.autoStartTitle) == "Launch at Login")
        #expect(loc.t(.menuToggleAutoStart) == "Launch at Login (Auto Start)")

        loc.selectedLanguage = .zh_tw
        #expect(loc.t(.autoStartTitle) == "開機時自動啟動")
        #expect(loc.t(.menuToggleAutoStart) == "開機時自動啟動 (Auto Start)")

        // 驗證視窗關閉時委派行為：隱藏視窗、切換為 .accessory 模式以隱藏 Dock 圖標
        let testWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let appDelegate = AppDelegate.shared
        appDelegate.registerMainWindow(testWindow)
        let shouldClose = appDelegate.windowShouldClose(testWindow)
        #expect(shouldClose == false)
        #expect(NSApp.activationPolicy() == .accessory)

        // 驗證從選單列重新開啟控制面板時，切換為 .regular 模式並顯示 Dock 圖標
        appDelegate.openControlPanel()
        #expect(NSApp.activationPolicy() == .regular)
    }
}
