//
//  TouchDeviceManager.swift
//  macTouchControl
//

import Foundation
import IOKit
import IOKit.hid
import CoreGraphics
import AppKit

@Observable
@MainActor
final class TouchDeviceManager {
    static let shared = TouchDeviceManager()

    var devices: [String: TouchDevice] = [:]
    var lastActiveDeviceID: String? = nil
    var lastTouchPoint: CGPoint? = nil
    var lastNormalizedPoint: CGPoint? = nil
    var isRunning: Bool = false

    /// 最近一次收到外接觸控硬體 IOHID 封包的系統時間戳
    private(set) var lastHardwarePacketTime: TimeInterval = 0

    /// 目前是否有任何外接觸控螢幕正處於硬體按壓接觸中（支援靜態定點長按，防止短時間無位移封包過早超時）
    var isHardwareTouchCurrentlyActive: Bool {
        let isTouching = devices.values.contains { $0.isTouching }
        let isDown = deviceStates.values.contains { $0.isDown }
        let isRecent = (ProcessInfo.processInfo.systemUptime - lastHardwarePacketTime < 1.5)
        return (isTouching || isDown) && isRecent
    }

    /// 判定事件是否源自觸控螢幕的操作（處於觸碰中，或剛在觸碰點附近抬起手指）
    func isTouchInteractionActive(at location: CGPoint) -> Bool {
        let uptime = ProcessInfo.processInfo.systemUptime
        let isTouching = devices.values.contains { $0.isTouching }
        let isDown = deviceStates.values.contains { $0.isDown }
        let isRecentPacket = (uptime - lastHardwarePacketTime < 1.5)

        // 1. 手指正在按壓螢幕（包含定點長按時靜止無封包狀態）
        if (isTouching || isDown) && isRecentPacket {
            return true
        }

        // 2. 手指剛抬起 800ms 內，若事件座標落在最後觸控點附近（120pt 內），判定為硬體或系統延遲派發的幽靈事件
        if uptime - lastTouchReleaseTime < 0.80 {
            if let lastPt = lastTouchPoint {
                let dist = hypot(location.x - lastPt.x, location.y - lastPt.y)
                if dist <= 120.0 {
                    return true
                }
            } else {
                return true
            }
        }

        return false
    }

    /// 目前外接觸控螢幕在全域座標系中的邊界（供事件隔離）
    var activeTouchDisplayBounds: CGRect? {
        guard let id = lastActiveDeviceID ?? devices.keys.first else { return nil }
        let displayManager = DisplayManager.shared
        let mappingStore = MappingStore.shared
        if displayManager.isMirroringActive {
            return displayManager.mainDisplay?.bounds
        }
        let target = mappingStore.targetDisplay(for: id, availableDisplays: displayManager.displays)
            ?? displayManager.displays.first(where: { !$0.isBuiltin })
            ?? displayManager.mainDisplay
        return target?.bounds
    }

    /// 目前是否有任何外接觸控螢幕處於按壓接觸中
    var isAnyTouchActive: Bool {
        isHardwareTouchCurrentlyActive
    }

    /// 上次手指離開觸控螢幕的時間戳
    private(set) var lastTouchReleaseTime: TimeInterval = 0

    private var hidManager: IOHIDManager?
    private let gestureHandler = TouchGestureHandler.shared

    // MARK: - Hardware Rogue Event Interceptor (CGEventTap 幽靈事件過濾器)
    private var eventTapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // 儲存每個裝置的內部狀態以維持拖曳與點擊連貫，並支援 X/Y 封包原子性合併
    private var deviceStates: [String: DeviceInputState] = [:]

    private struct DeviceInputState {
        var rawX: Double = 0
        var rawY: Double = 0
        var isDown: Bool = false
        var pendingXUpdate: Bool = false
        var hasTipSwitch: Bool = false
    }

    init() {
        start()
    }

    func start() {
        guard hidManager == nil else { return }

        // 啟動底層事件攔截器（阻斷系統幽靈拖曳、誤選取文字與非預期右鍵）
        setupEventTap()

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = manager

        // 匹配外部觸控螢幕、數位板 (Digitizer) 與觸控筆
        let matchingCriteria: [[String: Any]] = [
            [kIOHIDDeviceUsagePageKey as String: kHIDPage_Digitizer],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchingCriteria as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        // 註冊裝置連線回呼
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, sender, device in
            guard let context else { return }
            let manager = Unmanaged<TouchDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleDeviceConnected(device)
        }, context)

        // 註冊裝置拔除回呼
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, sender, device in
            guard let context else { return }
            let manager = Unmanaged<TouchDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleDeviceRemoved(device)
        }, context)

        // 註冊即時數值輸入回呼
        IOHIDManagerRegisterInputValueCallback(manager, { context, result, sender, value in
            guard let context else { return }
            let manager = Unmanaged<TouchDeviceManager>.fromOpaque(context).takeUnretainedValue()
            manager.handleInputValue(value)
        }, context)

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.isRunning = (openStatus == kIOReturnSuccess)
    }

    func stop() {
        tearDownEventTap()
        guard let manager = hidManager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.hidManager = nil
        self.isRunning = false
        MainActor.assumeIsolated {
            self.devices.removeAll()
            self.deviceStates.removeAll()
        }
    }

    func rescan() {
        stop()
        start()
    }

    // MARK: - CGEventTap 幽靈事件防護盾 (阻斷 macOS 內核產生的誤反白、拖曳與幽靈右鍵)

    func setupEventTap() {
        guard eventTapPort == nil else { return }
        guard PermissionManager.shared.isAccessibilityGranted else { return }

        let mask: CGEventMask = (CGEventMask(1) << CGEventType.leftMouseDown.rawValue) |
                                (CGEventMask(1) << CGEventType.leftMouseDragged.rawValue) |
                                (CGEventMask(1) << CGEventType.leftMouseUp.rawValue) |
                                (CGEventMask(1) << CGEventType.rightMouseDown.rawValue) |
                                (CGEventMask(1) << CGEventType.rightMouseDragged.rawValue) |
                                (CGEventMask(1) << CGEventType.rightMouseUp.rawValue) |
                                (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) |
                                (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue) |
                                (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<TouchDeviceManager>.fromOpaque(refcon).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = manager.eventTapPort {
                        CGEvent.tapEnable(tap: port, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                // 1. 檢查是否為 macTouchControl 主動合成發送的白名單事件（簽名 0x544F5543 = "TOUC"）
                let signature = event.getIntegerValueField(.eventSourceUserData)
                if signature == TouchGestureHandler.synthesizedEventSignature {
                    // 由本程式經手勢引擎精準判定後合法派發的點擊與拖曳，完全放行
                    return Unmanaged.passUnretained(event)
                }

                // 2. 螢幕空間隔離：若事件座標不在外接觸控螢幕內（例如在 MacBook 內建螢幕），100% 放行，絕不干擾主螢幕滑鼠！
                let location = event.location
                guard let touchBounds = manager.activeTouchDisplayBounds, touchBounds.contains(location) else {
                    return Unmanaged.passUnretained(event)
                }

                // 3. 判斷是否為觸控螢幕交互產生的硬體或系統事件（按壓中或剛抬起於落指點附近）
                let isFromTouch = manager.isTouchInteractionActive(at: location)
                guard isFromTouch else {
                    // 非觸控產生的事件（如桌面上實體滑鼠的操作），100% 放行
                    return Unmanaged.passUnretained(event)
                }

                // 4. 右鍵與次鍵事件攔截（長按右鍵沒開就絕對不要出現；有系統事件也要徹底攔截）：
                // 凡來自觸控螢幕且未經 macTouchControl 白名單認證的系統右鍵（rightMouseDown/rightMouseUp/Control+Click 等），一律攔截捨棄！
                let isRightClick = (type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp) ||
                                   (type == .leftMouseDown && event.flags.contains(.maskControl))
                if isRightClick {
                    return nil
                }

                // 5. 其他按鍵（如滾輪中鍵等未授權幽靈事件），一律攔截
                if type == .otherMouseDown || type == .otherMouseDragged || type == .otherMouseUp {
                    return nil
                }

                // 6. 左鍵事件攔截（全面攔截未授權的硬體原始拖曳/點擊，統一由 TouchGestureHandler 精準派發，防止與手勢引擎衝突）
                return nil

                return Unmanaged.passUnretained(event)
            },
            userInfo: observer
        ) else {
            return
        }

        self.eventTapPort = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func tearDownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            self.runLoopSource = nil
        }
        if let tap = eventTapPort {
            CGEvent.tapEnable(tap: tap, enable: false)
            self.eventTapPort = nil
        }
    }

    // MARK: - Device Filtering

    /// 判斷裝置是否為可調用與綁定的外接觸控螢幕／數位板，排除 Mac 內建鍵盤觸控板與常規輸入設備
    nonisolated static func isEligibleTouchDevice(name: String, manufacturer: String, vendorID: Int, isBuiltIn: Bool) -> Bool {
        // 1. 內建硬體一律排除
        if isBuiltIn {
            return false
        }

        let lowerName = name.lowercased()
        let lowerManufacturer = manufacturer.lowercased()

        // 2. 排除所有 Apple 原生設備 (Vendor ID 0x05AC = 1452)
        // Apple 設備均為 Mac 內建鍵盤/觸控板、Magic Trackpad、Magic Mouse 等，非外接觸控螢幕
        if vendorID == 0x05AC || lowerManufacturer.contains("apple") {
            return false
        }

        // 3. 排除名稱中帶有 Internal / Trackpad / Keyboard / Touch Bar 等關鍵字的設備
        if lowerName.contains("internal") ||
           lowerName.contains("trackpad") ||
           lowerName.contains("keyboard") ||
           lowerName.contains("touch bar") {
            return false
        }

        // 4. 排除純滑鼠設備（名稱含 mouse 且不含 touch / digitizer / screen）
        if lowerName.contains("mouse") && !lowerName.contains("touch") && !lowerName.contains("digitizer") && !lowerName.contains("screen") {
            return false
        }

        return true
    }

    // MARK: - Device Lifecycle

    private func deviceID(for device: IOHIDDevice) -> String {
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let locationID = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String

        let locationPart = locationID != nil ? "\(locationID!)" : "0"
        let serialPart = serial ?? locationPart
        return "\(vendorID)_\(productID)_\(serialPart)"
    }

    private func handleDeviceConnected(_ device: IOHIDDevice) {
        let defaultName = LocalizationManager.shared.t(.defaultTouchDeviceName)
        let name = (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String) ?? defaultName
        let manufacturer = (IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString) as? String) ?? ""
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue ?? 0
        let locationID = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.intValue
        let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String

        // 檢查 Built-In 屬性
        var isBuiltIn = false
        if let b = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? Bool {
            isBuiltIn = b
        } else if let num = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) as? NSNumber {
            isBuiltIn = num.boolValue
        } else if let str = IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? String {
            isBuiltIn = (str.lowercased() == "true")
        }

        // 若不是可調用/可映射的外接觸控設備，則直接忽略不予註冊與顯示
        guard Self.isEligibleTouchDevice(name: name, manufacturer: manufacturer, vendorID: vendorID, isBuiltIn: isBuiltIn) else {
            return
        }

        let id = deviceID(for: device)

        var minX: Double = 0
        var maxX: Double = 32767
        var minY: Double = 0
        var maxY: Double = 32767

        // 讀取裝置 Elements 以校準座標範圍
        if let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for element in elements {
                let page = Int(IOHIDElementGetUsagePage(element))
                let usage = Int(IOHIDElementGetUsage(element))

                if page == kHIDPage_GenericDesktop {
                    if usage == kHIDUsage_GD_X {
                        let eMin = Double(IOHIDElementGetLogicalMin(element))
                        let eMax = Double(IOHIDElementGetLogicalMax(element))
                        if eMax > eMin {
                            minX = eMin
                            maxX = eMax
                        }
                    } else if usage == kHIDUsage_GD_Y {
                        let eMin = Double(IOHIDElementGetLogicalMin(element))
                        let eMax = Double(IOHIDElementGetLogicalMax(element))
                        if eMax > eMin {
                            minY = eMin
                            maxY = eMax
                        }
                    }
                }
            }
        }

        let touchDevice = TouchDevice(
            id: id,
            name: name,
            manufacturer: manufacturer,
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            serialNumber: serial,
            isDigitizer: true,
            minX: minX,
            maxX: maxX,
            minY: minY,
            maxY: maxY
        )

        MainActor.assumeIsolated {
            self.devices[id] = touchDevice
            self.deviceStates[id] = DeviceInputState()

            // 確保 EventTap 已就緒
            if self.eventTapPort == nil {
                self.setupEventTap()
            }

            // 只有在此裝置完全沒有任何儲存的綁定記錄時，才為新裝置自動配對預設螢幕；若已曾綁定過則保持記錄，等待螢幕接回
            let mappingStore = MappingStore.shared
            let displayManager = DisplayManager.shared
            if mappingStore.mappings[id] == nil {
                // 若有外接螢幕則嘗試配對第一個外接，否則使用主螢幕
                let targetDisplay = displayManager.displays.first(where: { !$0.isBuiltin }) ?? displayManager.mainDisplay
                if let targetDisplay {
                    mappingStore.bind(deviceID: id, deviceName: name, display: targetDisplay)
                }
            }
        }
    }

    private func handleDeviceRemoved(_ device: IOHIDDevice) {
        let id = deviceID(for: device)
        MainActor.assumeIsolated {
            self.devices.removeValue(forKey: id)
            self.deviceStates.removeValue(forKey: id)
            if self.lastActiveDeviceID == id {
                self.lastActiveDeviceID = nil
            }
        }
    }

    // MARK: - Input Value Handling (封包合併與零延遲跟手架構)

    private func handleInputValue(_ value: IOHIDValue) {
        lastHardwarePacketTime = ProcessInfo.processInfo.systemUptime

        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let id = deviceID(for: device)

        let page = Int(IOHIDElementGetUsagePage(element))
        let usage = Int(IOHIDElementGetUsage(element))
        let intVal = IOHIDValueGetIntegerValue(value)

        var state = deviceStates[id] ?? DeviceInputState()
        var coordinateUpdated = false
        var tipChanged = false

        if page == kHIDPage_GenericDesktop {
            if usage == kHIDUsage_GD_X {
                state.rawX = Double(intVal)
                state.pendingXUpdate = true
                deviceStates[id] = state

                // 採用 commonModes 並即刻喚醒 RunLoop，保證在事件追蹤（Tracking）期間絕不延遲滯留
                let runLoop = CFRunLoopGetMain()
                CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) { [weak self] in
                    guard let self else { return }
                    MainActor.assumeIsolated {
                        var curState = self.deviceStates[id] ?? state
                        if curState.pendingXUpdate {
                            curState.pendingXUpdate = false
                            self.deviceStates[id] = curState
                            self.processTouchInput(id: id, state: curState, tipChanged: false)
                        }
                    }
                }
                CFRunLoopWakeUp(runLoop)
                return
            } else if usage == kHIDUsage_GD_Y {
                state.rawY = Double(intVal)
                state.pendingXUpdate = false // Y 軸到達，直接合併 X 與 Y 立即觸發，杜絕拆包橫縱分離
                coordinateUpdated = true
            }
        } else if page == kHIDPage_Digitizer {
            if usage == kHIDUsage_Dig_TipSwitch {
                state.hasTipSwitch = true
                let newDown = (intVal > 0)
                if newDown != state.isDown {
                    state.isDown = newDown
                    tipChanged = true
                }
            }
        } else if page == kHIDPage_Button {
            if usage == 1 { // Button 1
                // 只有在裝置未曾回報過 Digitizer TipSwitch 時，才由 Button 1 決定觸碰狀態，防止雙報告競爭抖動
                if !state.hasTipSwitch {
                    let newDown = (intVal > 0)
                    if newDown != state.isDown {
                        state.isDown = newDown
                        tipChanged = true
                    }
                }
            }
        }

        deviceStates[id] = state

        guard coordinateUpdated || tipChanged else { return }

        // 同步在主執行緒立即處理觸控事件，杜絕 Task 異步隊列造成的延遲跟手問題
        MainActor.assumeIsolated {
            self.processTouchInput(id: id, state: state, tipChanged: tipChanged)
        }
    }

    @MainActor
    private func processTouchInput(id: String, state: DeviceInputState, tipChanged: Bool) {
        guard let touchDevice = self.devices[id] else { return }

        // 若 EventTap 尚未啟動（例如啟動後才取得 Accessibility 權限），動態補救建立
        if self.eventTapPort == nil {
            self.setupEventTap()
        }

        let displayManager = DisplayManager.shared
        let mappingStore = MappingStore.shared

        // 計算標準化座標 (0.0 ... 1.0)
        let normPoint = touchDevice.normalizedCoordinate(rawX: state.rawX, rawY: state.rawY)

        // 尋找綁定的目標螢幕（若鏡像中或未自訂則使用主螢幕）
        let targetDisplay: DisplayInfo?
        if displayManager.isMirroringActive {
            targetDisplay = displayManager.mainDisplay
        } else {
            targetDisplay = mappingStore.targetDisplay(for: id, availableDisplays: displayManager.displays) ?? displayManager.mainDisplay
        }

        guard let display = targetDisplay else { return }

        // 映射至目標螢幕的全域 CoreGraphics 座標
        let targetBounds = display.bounds
        let screenX = targetBounds.origin.x + normPoint.x * targetBounds.width
        let screenY = targetBounds.origin.y + normPoint.y * targetBounds.height
        let targetPoint = CGPoint(x: screenX, y: screenY)

        // 核心功能：游標立馬無延遲跳轉至對應螢幕
        CGWarpMouseCursorPosition(targetPoint)

        // 更新即時狀態指示與手指釋放時間戳
        self.lastActiveDeviceID = id
        self.lastTouchPoint = targetPoint
        self.lastNormalizedPoint = normPoint
        self.devices[id]?.currentRawX = state.rawX
        self.devices[id]?.currentRawY = state.rawY

        if self.devices[id]?.isTouching == true && !state.isDown {
            self.lastTouchReleaseTime = ProcessInfo.processInfo.systemUptime
        }
        self.devices[id]?.isTouching = state.isDown
        self.devices[id]?.lastActiveTime = Date()

        // 交付手勢與觸控事件引擎（支援平板滑動、防誤觸輕點、Windows 風格長按右鍵、側滑開通知中心與 2D 慣性）
        self.gestureHandler.handleTouch(
            point: targetPoint,
            normalized: normPoint,
            targetBounds: targetBounds,
            isDown: state.isDown,
            tipChanged: tipChanged
        )

        // 若裝置支援近距懸停（未觸碰且未改變狀態），發送 MouseMoved
        if !state.isDown && !tipChanged {
            guard PermissionManager.shared.isAccessibilityGranted else { return }
            let event = CGEvent(
                mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: targetPoint,
                mouseButton: .left
            )
            event?.setIntegerValueField(.eventSourceUserData, value: TouchGestureHandler.synthesizedEventSignature)
            event?.post(tap: .cghidEventTap)
        }
    }
}
