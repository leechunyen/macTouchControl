//
//  TouchDevice.swift
//  macTouchControl
//

import Foundation
import CoreGraphics

struct TouchDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let manufacturer: String
    let vendorID: Int
    let productID: Int
    let locationID: Int?
    let serialNumber: String?
    let isDigitizer: Bool

    // 觸控座標邏輯/物理範圍校準
    var minX: Double = 0
    var maxX: Double = 32767
    var minY: Double = 0
    var maxY: Double = 32767

    // 即時狀態
    var currentRawX: Double = 0
    var currentRawY: Double = 0
    var isTouching: Bool = false
    var lastActiveTime: Date? = nil

    init(
        id: String,
        name: String,
        manufacturer: String = "",
        vendorID: Int = 0,
        productID: Int = 0,
        locationID: Int? = nil,
        serialNumber: String? = nil,
        isDigitizer: Bool = true,
        minX: Double = 0,
        maxX: Double = 32767,
        minY: Double = 0,
        maxY: Double = 32767
    ) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serialNumber = serialNumber
        self.isDigitizer = isDigitizer
        self.minX = minX
        self.maxX = maxX
        self.minY = minY
        self.maxY = maxY
    }

    var isActiveRecently: Bool {
        guard let lastActiveTime else { return false }
        return Date().timeIntervalSince(lastActiveTime) < 1.5
    }

    var displayLabel: String {
        if manufacturer.isEmpty {
            return "\(name) [VID: 0x\(String(vendorID, radix: 16, uppercase: true)) PID: 0x\(String(productID, radix: 16, uppercase: true))]"
        }
        return "\(manufacturer) - \(name)"
    }

    /// 將原始 HID 座標轉換為標準化 (0...1, 0...1) 比例
    func normalizedCoordinate(rawX: Double, rawY: Double) -> CGPoint {
        let spanX = max(maxX - minX, 1.0)
        let spanY = max(maxY - minY, 1.0)

        let normX = max(0.0, min(1.0, (rawX - minX) / spanX))
        let normY = max(0.0, min(1.0, (rawY - minY) / spanY))

        return CGPoint(x: normX, y: normY)
    }

    static func == (lhs: TouchDevice, rhs: TouchDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
