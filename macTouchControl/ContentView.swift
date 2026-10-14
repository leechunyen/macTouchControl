//
//  ContentView.swift
//  macTouchControl
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(PermissionManager.self) private var permissionManager
    @Environment(DisplayManager.self) private var displayManager
    @Environment(TouchDeviceManager.self) private var touchManager
    @Environment(MappingStore.self) private var mappingStore
    @Environment(LocalizationManager.self) private var loc
    @Environment(TouchGestureHandler.self) private var gestureHandler

    @State private var isPermissionSectionExpanded: Bool? = nil
    @State private var isGesturesSectionExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 頂部應用程式狀態列
            headerView

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // 1. 權限檢查與配置卡片（具備權限時自動預設折疊）
                    permissionStatusSection

                    // 2. 觸控面板與螢幕 1-to-1 綁定卡片
                    deviceMappingSection

                    // 3. 螢幕資訊一覽
                    displaysOverviewSection

                    // 4. 手勢與捲動功能區（支援折疊）
                    upcomingGesturesSection
                }
                .padding(20)
            }
        }
        .frame(minWidth: 720, idealWidth: 760, minHeight: 660, idealHeight: 700)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Header
    private var headerView: some View {
        HStack {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 26))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("macTouchControl")
                    .font(.title2)
                    .fontWeight(.bold)
                Text(loc.t(.appSubtitle))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // 語言切換選擇器
            Picker("", selection: Binding<AppLanguage>(
                get: { loc.selectedLanguage },
                set: { loc.selectedLanguage = $0 }
            )) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 170)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Permission Section
    private var isPermissionsExpanded: Bool {
        isPermissionSectionExpanded ?? !permissionManager.isAllGranted
    }

    private var permissionStatusSection: some View {
        VStack(alignment: .leading, spacing: isPermissionsExpanded ? 14 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isPermissionSectionExpanded == nil {
                        isPermissionSectionExpanded = permissionManager.isAllGranted
                    } else {
                        isPermissionSectionExpanded?.toggle()
                    }
                }
            } label: {
                HStack {
                    Label(loc.t(.permissionSectionTitle), systemImage: "shield.lefthalf.filled")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    if permissionManager.isAllGranted {
                        Text(loc.t(.permissionAllGranted))
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(6)
                    } else {
                        Text(loc.t(.permissionMissingWarning))
                            .font(.caption)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(6)
                    }

                    Image(systemName: isPermissionsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isPermissionsExpanded {
                VStack(spacing: 12) {
                    permissionRow(
                        title: loc.t(.accessibilityTitle),
                        description: loc.t(.accessibilityDesc),
                        isGranted: permissionManager.isAccessibilityGranted,
                        action: { permissionManager.requestAccessibility() }
                    )

                    Divider()

                    permissionRow(
                        title: loc.t(.inputMonitoringTitle),
                        description: loc.t(.inputMonitoringDesc),
                        isGranted: permissionManager.isInputMonitoringGranted,
                        action: { permissionManager.requestInputMonitoring() }
                    )

                    // 拖曳授權輔助說明提示
                    if !permissionManager.isAllGranted {
                        Divider()

                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(loc.t(.dragHelperTitle))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(loc.t(.dragHelperDesc))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer()

                            Button(loc.t(.revealInFinderButton)) {
                                permissionManager.revealAppInFinder()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                        .padding(10)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func permissionRow(
        title: String,
        description: String,
        isGranted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(isGranted ? .green : .orange)
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Text(loc.t(.permissionGrantedBadge))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
            } else {
                Button(loc.t(.permissionRequestButton), action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Device Mapping Section
    private var deviceMappingSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(loc.t(.mappingSectionTitle), systemImage: "hand.tap")
                    .font(.headline)

                Spacer()

                Button {
                    touchManager.rescan()
                    displayManager.refreshDisplays()
                } label: {
                    Label(loc.t(.rescanButton), systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if displayManager.isMirroringActive {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.on.rectangle")
                        .foregroundColor(.blue)
                    Text(loc.t(.mirrorModeNotice))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(8)
            }

            let deviceList = Array(touchManager.devices.values)

            if deviceList.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "cable.connector.slash")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(loc.t(.noDeviceDetectedTitle))
                        .font(.headline)
                    Text(loc.t(.noDeviceDetectedDesc))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
            } else {
                ForEach(deviceList) { device in
                    deviceCard(device: device)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func deviceCard(device: TouchDevice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: device.isDigitizer ? "hand.draw" : "hand.tap")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name)
                        .font(.headline)
                    Text("\(device.manufacturer.isEmpty ? "HID" : device.manufacturer) - \(device.name)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if device.isActiveRecently {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(loc.t(.touchSignalActive))
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Divider()

            // 綁定設定選擇器
            HStack(spacing: 12) {
                Text(loc.t(.mappedDisplayLabel))
                    .font(.subheadline)
                    .fontWeight(.medium)

                let currentTarget = mappingStore.targetDisplay(for: device.id, availableDisplays: displayManager.displays)

                Picker("", selection: Binding<CGDirectDisplayID>(
                    get: { currentTarget?.id ?? displayManager.mainDisplay?.id ?? 0 },
                    set: { newID in
                        if let selectedDisplay = displayManager.displays.first(where: { $0.id == newID }) {
                            mappingStore.bind(deviceID: device.id, deviceName: device.name, display: selectedDisplay)
                        }
                    }
                )) {
                    ForEach(displayManager.displays) { display in
                        Text(display.displayNameWithDetails(loc: loc)).tag(display.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)

                Spacer()

                // 測試跳轉按鈕
                Button(loc.t(.testWarpButton)) {
                    if let target = currentTarget ?? displayManager.mainDisplay {
                        let center = CGPoint(x: target.bounds.midX, y: target.bounds.midY)
                        CGWarpMouseCursorPosition(center)
                    }
                }
                .buttonStyle(.bordered)
            }

            // 即時偵測資訊狀態
            if device.lastActiveTime != nil {
                let curX = device.currentRawX
                let curY = device.currentRawY
                let norm = device.normalizedCoordinate(rawX: curX, rawY: curY)
                HStack(spacing: 16) {
                    Text(loc.t(.liveCoordinates(Int(curX), Int(curY))))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(loc.t(.panelRatio(norm.x, norm.y)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(device.isActiveRecently ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
    }

    // MARK: - Displays Overview Section
    private var displaysOverviewSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(loc.t(.displaysSectionTitle(displayManager.displays.count)), systemImage: "tv")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(displayManager.displays) { display in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                                .foregroundColor(.accentColor)
                            Text(display.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            if display.isMain {
                                Text(loc.t(.mainDisplayBadge))
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }

                        Text(loc.t(.resolution(Int(display.pixelWidth), Int(display.pixelHeight))))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text(loc.t(.origin(Int(display.bounds.origin.x), Int(display.bounds.origin.y))))
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        // 顯示綁定到此螢幕的觸控裝置
                        let mappedDevices = touchManager.devices.values.filter { dev in
                            mappingStore.targetDisplay(for: dev.id, availableDisplays: displayManager.displays)?.id == display.id
                        }
                        if !mappedDevices.isEmpty {
                            Text(loc.t(.mappedDeviceList(mappedDevices.map(\.name).joined(separator: ", "))))
                                .font(.caption2)
                                .foregroundColor(.accentColor)
                                .lineLimit(1)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    // MARK: - Upcoming Gestures Section
    private var upcomingGesturesSection: some View {
        VStack(alignment: .leading, spacing: isGesturesSectionExpanded ? 14 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isGesturesSectionExpanded.toggle()
                }
            } label: {
                HStack {
                    Label(loc.t(.gesturesSectionTitle), systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text(gestureHandler.isTouchScrollEnabled ? loc.t(.nextPhaseBadge) : loc.t(.comingSoonBadge))
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(gestureHandler.isTouchScrollEnabled ? Color.green.opacity(0.12) : Color.purple.opacity(0.12))
                        .foregroundColor(gestureHandler.isTouchScrollEnabled ? .green : .purple)
                        .cornerRadius(6)

                    Image(systemName: isGesturesSectionExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isGesturesSectionExpanded {
                VStack(spacing: 12) {
                    // 1. Tablet 風格雙向滑動開關（已完成功能）
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            Image(systemName: "hand.draw")
                                .font(.system(size: 20))
                                .foregroundColor(.accentColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc.t(.gestureScrollTitle))
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text(loc.t(.gestureScrollDesc))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            Toggle("", isOn: Binding<Bool>(
                                get: { gestureHandler.isTouchScrollEnabled },
                                set: { gestureHandler.isTouchScrollEnabled = $0 }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                        }

                        if gestureHandler.isTouchScrollEnabled {
                            Divider()

                            HStack {
                                Text(loc.t(.naturalScrollTitle))
                                    .font(.subheadline)
                                Text(loc.t(.naturalScrollDesc))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Toggle("", isOn: Binding<Bool>(
                                    get: { gestureHandler.naturalScroll },
                                    set: { gestureHandler.naturalScroll = $0 }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                            }
                            .padding(.leading, 28)

                            HStack {
                                Text(loc.t(.scrollSensitivityTitle))
                                    .font(.subheadline)

                                Spacer()

                                Slider(
                                    value: Binding<Double>(
                                        get: { gestureHandler.scrollSensitivity },
                                        set: { gestureHandler.scrollSensitivity = $0 }
                                    ),
                                    in: 0.5...3.0,
                                    step: 0.1
                                )
                                .frame(width: 140)

                                Text(String(format: "%.1fx", gestureHandler.scrollSensitivity))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .padding(.leading, 28)
                        }
                    }
                    .padding(12)
                    .background(gestureHandler.isTouchScrollEnabled ? Color.accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    Divider()

                    // 2. Windows 風格長按觸發右鍵（已完成功能，預設開啟，使用者可自由切換）
                    HStack(alignment: .center) {
                        Image(systemName: "cursorarrow.click.2")
                            .font(.system(size: 20))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc.t(.longPressRightClickTitle))
                                .font(.body)
                                .fontWeight(.medium)
                            Text(loc.t(.longPressRightClickDesc))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: Binding<Bool>(
                            get: { gestureHandler.isLongPressRightClickEnabled },
                            set: { gestureHandler.isLongPressRightClickEnabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }
                    .padding(12)
                    .background(gestureHandler.isLongPressRightClickEnabled ? Color.accentColor.opacity(0.06) : Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)

                    Divider()

                    // 3. 右側邊緣向內滑開通知中心（即將推出）
                    gesturePreviewRow(
                        title: loc.t(.gestureNotificationCenterTitle),
                        description: loc.t(.gestureNotificationCenterDesc),
                        icon: "sidebar.right",
                        comingSoonBadge: loc.t(.comingSoonBadge)
                    )

                    Divider()

                    // 4. 底部邊緣向內滑顯示 Dock（即將推出）
                    gesturePreviewRow(
                        title: loc.t(.gestureDockTitle),
                        description: loc.t(.gestureDockDesc),
                        icon: "dock.rectangle",
                        comingSoonBadge: loc.t(.comingSoonBadge)
                    )
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }

    private func gesturePreviewRow(
        title: String,
        description: String,
        icon: String,
        comingSoonBadge: String
    ) -> some View {
        HStack(alignment: .center) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(comingSoonBadge)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.12))
                .foregroundColor(.purple)
                .cornerRadius(6)
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}
