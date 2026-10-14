//
//  macTouchControlTests.swift
//  macTouchControlTests
//
//  Created by LeeChunYen on 14/10/2026.
//

import Testing
import CoreGraphics
@testable import macTouchControl

@Suite("macTouchControl 核心邏輯與多語言測試")
struct MacTouchControlTests {

    @Test("測試語言自動檢測與Fallback機制")
    func testLanguageDetectionAndFallback() {
        // 1. 繁體中文台灣優先 -> zh_tw
        let zhTWResult = LocalizationManager.resolveLanguage(from: ["zh-TW", "en-US"])
        #expect(zhTWResult == .zh_tw)

        // 2. zh-Hant-TW 格式 -> zh_tw
        let zhHantResult = LocalizationManager.resolveLanguage(from: ["zh-Hant-TW", "en"])
        #expect(zhHantResult == .zh_tw)

        // 3. 香港繁體 -> zh_tw
        let zhHKResult = LocalizationManager.resolveLanguage(from: ["zh-HK", "en"])
        #expect(zhHKResult == .zh_tw)

        // 4. 英文優先 -> en_us
        let enResult = LocalizationManager.resolveLanguage(from: ["en-US", "zh-TW"])
        #expect(enResult == .en_us)

        // 5. 非支援語言（日語、法語、德語等） -> 必須一律 fallback 去 en_us
        let jaResult = LocalizationManager.resolveLanguage(from: ["ja-JP", "es-ES"])
        #expect(jaResult == .en_us)

        let frResult = LocalizationManager.resolveLanguage(from: ["fr-FR"])
        #expect(frResult == .en_us)

        let emptyResult = LocalizationManager.resolveLanguage(from: [])
        #expect(emptyResult == .en_us)
    }

    @Test("測試動態語系切換字串轉換")
    @MainActor
    func testLocalizedStrings() {
        let loc = LocalizationManager()

        // 切換為繁體中文
        loc.selectedLanguage = .zh_tw
        #expect(loc.currentEffectiveLanguage == .zh_tw)
        #expect(loc.t(.appName) == "macTouchControl")
        #expect(loc.t(.statusActive) == "服務運作中")
        #expect(loc.t(.revealInFinderButton) == "在 Finder 中顯示 App")
        #expect(loc.t(.menuQuit) == "離開 macTouchControl")

        // 切換為英文
        loc.selectedLanguage = .en_us
        #expect(loc.currentEffectiveLanguage == .en_us)
        #expect(loc.t(.statusActive) == "Service Active")
        #expect(loc.t(.revealInFinderButton) == "Reveal App in Finder")
        #expect(loc.t(.menuQuit) == "Quit macTouchControl")
    }

    @Test("測試觸控設備座標標準化與邊界約束")
    func testCoordinateNormalization() {
        let device = TouchDevice(
            id: "test_dev_1",
            name: "測試觸控板",
            manufacturer: "TestCorp",
            vendorID: 0x1234,
            productID: 0x5678,
            locationID: 1,
            serialNumber: "SN123",
            isDigitizer: true,
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
}
