//
//  macTouchControlTests.swift
//  macTouchControlTests
//
//  Created by LeeChunYen on 14/10/2026.
//

import Testing
import Foundation
import CoreGraphics
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
        let manager = LocalizationManager()

        // 強制切換為英文
        manager.selectedLanguage = .en_us
        #expect(manager.t(.statusActive) == "Service Active")
        #expect(manager.t(.mappingSectionTitle) == "Touch Panel & Display 1-to-1 Mapping")
        #expect(manager.t(.accessibilityTitle) == "Accessibility")
        #expect(manager.t(.mainDisplayBadge) == "Main")
        #expect(manager.t(.gestureScrollTitle) == "Touchscreen 2D Scrolling (Tablet Mode)")
        #expect(manager.t(.longPressRightClickTitle) == "Long Press for Right-Click (Windows Style)")

        // 強制切換為繁體中文（嚴格台灣用語：裝置、螢幕、捲動、預設）
        manager.selectedLanguage = .zh_tw
        #expect(manager.t(.statusActive) == "服務運作中")
        #expect(manager.t(.mappingSectionTitle) == "觸控面板與螢幕 1 對 1 綁定")
        #expect(manager.t(.rescanButton) == "重新掃描裝置")
        #expect(manager.t(.defaultTouchDeviceName) == "觸控裝置")
        #expect(manager.t(.accessibilityTitle) == "輔助使用 (Accessibility)")
        #expect(manager.t(.mainDisplayBadge) == "主螢幕")
        #expect(manager.t(.gestureScrollTitle) == "觸控螢幕雙向捲動 (平板 / 手機模式)")
        #expect(manager.t(.naturalScrollTitle) == "自然捲動方向 (Natural Scrolling)")
        #expect(manager.t(.longPressRightClickTitle) == "長按觸發右鍵 (如同 Windows 觸控體驗)")
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

        // 測試螢幕重新連線後 DisplayID 變更但名稱相符的模糊修復匹配
        let reconnectedDisplay = DisplayInfo(
            id: 202,
            name: "外接觸控螢幕 A",
            bounds: CGRect(x: 1920, y: 0, width: 1920, height: 1080),
            pixelWidth: 1920,
            pixelHeight: 1080,
            isMain: false,
            isBuiltin: false,
            isMirror: false
        )
        let fallbackMatched = store.targetDisplay(for: "dev_touch_1", availableDisplays: [reconnectedDisplay])
        #expect(fallbackMatched?.id == 202)

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

    @Test("測試平板觸控滑動手勢處理器預設值、雙向捲動與防誤觸點擊")
    @MainActor
    func testTouchGestureHandlerCycle() {
        // 先清除持久化快取，以驗證乾淨環境下的預設值
        UserDefaults.standard.removeObject(forKey: "macTouchControl.touchScrollEnabled")
        UserDefaults.standard.removeObject(forKey: "macTouchControl.naturalScroll")
        UserDefaults.standard.removeObject(forKey: "macTouchControl.scrollSensitivity")

        let handler = TouchGestureHandler()

        // 需求4：觸摸屏滑動體驗和自然滑動方向必須默認開啟
        #expect(handler.isTouchScrollEnabled == true)
        #expect(handler.naturalScroll == true)
        #expect(handler.scrollSensitivity == 1.0)

        let tapPoint = CGPoint(x: 200, y: 300)
        let norm = CGPoint(x: 0.2, y: 0.3)

        // 模擬正常輕點 Tap（在有效時間與微小位移內快速釋放）
        handler.handleTouch(point: tapPoint, normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: tapPoint, normalized: norm, isDown: false, tipChanged: true)

        // 模擬垂直與水平 2D 滑動循環（支援橫向與上下捲動）
        let scrollStart = CGPoint(x: 300, y: 400)
        handler.handleTouch(point: scrollStart, normalized: norm, isDown: true, tipChanged: true)

        // 移動水平 (dx = +30) 與垂直 (dy = +40) 像素，超過 4.0 點閥值立即觸發雙向捲動
        let scrollMove1 = CGPoint(x: 330, y: 440)
        handler.handleTouch(point: scrollMove1, normalized: norm, isDown: true, tipChanged: false)

        let scrollMove2 = CGPoint(x: 380, y: 500)
        handler.handleTouch(point: scrollMove2, normalized: norm, isDown: true, tipChanged: false)

        // 釋放手勢：由於處於 scrolling 狀態，絕對不會誤觸發左鍵點擊（防誤點擊）
        handler.handleTouch(point: scrollMove2, normalized: norm, isDown: false, tipChanged: true)

        // 模擬觸碰中斷可能存在的慣性滑行
        handler.handleTouch(point: CGPoint(x: 380, y: 500), normalized: norm, isDown: true, tipChanged: true)
        handler.handleTouch(point: CGPoint(x: 380, y: 500), normalized: norm, isDown: false, tipChanged: true)

        // 測試修改配置後，能重設回預設值
        handler.naturalScroll = false
        #expect(handler.naturalScroll == false)

        handler.scrollSensitivity = 1.5
        #expect(handler.scrollSensitivity == 1.5)

        handler.isTouchScrollEnabled = false
        #expect(handler.isTouchScrollEnabled == false)

        // 測試重設回預設值
        handler.isTouchScrollEnabled = true
        handler.naturalScroll = true
        handler.scrollSensitivity = 1.0
    }
}
