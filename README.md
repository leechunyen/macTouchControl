# macTouchControl

A modern, lightweight macOS utility designed for external touchscreen monitors and digitizers. Eliminates cursor-jumping issues across extended displays, brings natural 2D tablet scrolling, Windows/iPad-style long-press right-clicks, and screen edge gestures to Mac.

[![Platform](https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue.svg)](https://apple.com)
[![Language](https://img.shields.io/badge/Language-Swift%205.9%20%2F%20SwiftUI-orange.svg)](https://swift.org)
[![Architecture](https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-purple.svg)](https://apple.com)
[![License](https://img.shields.io/badge/License-GPL--3.0-green.svg)](LICENSE)
[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Donate-yellow.svg?logo=buy-me-a-coffee)](https://buymeacoffee.com/cylee99)

---

## 🌟 Key Features

### 1. 1-to-1 Touch Panel & Display Mapping
- **Eliminate Cursor Jumps**: macOS natively routes external touch inputs to the primary display (e.g., your built-in MacBook screen). `macTouchControl` locks the touch digitizer directly to your designated external monitor.
- **Smart Hot-Plug & Reconnect Persistence**: Remembers monitor bindings across reboots and sleep/wake cycles. Even if the USB topology or bus location ID changes when swapping ports, it intelligently restores bindings by hardware identifiers.
- **Display Identifier Overlays**: Press a single button to display clear visual identifier cards centered on each connected screen to instantly verify numbers and names.
- **Display Rotation Support**: Supports landscape and portrait orientations (0°, 90°, 180°, and 270°) with automatic coordinate matrix transformations.

### 2. Tablet-Style 2D Direct Manipulation Scrolling
- **Fluid Touch Scrolling**: Drag documents, code editors, and web pages naturally, mimicking iPadOS and smartphone touchscreen behavior.
- **Touch-to-Brake & Drag Protection**: Tapping the screen while content is scrolling instantly brakes momentum without triggering accidental clicks or selections.
- **Natural Scrolling & Sensitivity Tuning**: Toggle between Natural and Inverted scroll directions, with granular sensitivity adjustments via slider.

### 3. Windows / iPad-Style Long-Press Right-Click
- **Visual Countdown Ring Overlay**: Holding your finger in place displays an animated countdown ring with haptic feedback. Lifting your finger triggers a native right-click contextual menu.
- **Click Hold & Drag**: Keep dragging after the countdown ring completes to initiate an immediate left-button drag—ideal for selecting text blocks or moving files.
- **Smart Window Title Bar Dragging**: Instantly drag app windows across displays by pressing the window title bar without waiting for the long-press countdown.

### 4. Edge Swipe for macOS Notification Center
- Swipe inward from the right edge of your external touchscreen to summon or dismiss the macOS Notification Center specifically on that display.

### 5. Low-Level Ghost Event Interception Shield
- **Built-in CGEventTap Filter**: Suppresses unintended secondary hardware clicks, stray middle clicks, or duplicate system events dispatched by third-party touch controllers.
- **Multi-Touch Contact Tracking**: Complies with standard Windows Touch Digitizer specifications (Usage Page `0x0D`, Usage `0x51`). Tracks primary touch contacts while ignoring secondary contacts to prevent cursor jitter.
- **Physical Mouse Isolation**: Touch shielding only takes effect within the active finger touch radius; your desk mouse remains fully operational and unimpeded.

### 6. Lightweight Menu Bar App
- **Menu Bar Resident**: Resides unobtrusively in your macOS status menu bar. Closing the settings window hides the Dock icon and keeps the app running quietly in the background.
- **Full Spotlight / Launchpad Integration**: Re-opening the app from Spotlight, Launchpad, or Finder instantly brings back the preferences window.
- **Auto-Start at Login**: Built-in `SMAppService` launch-at-login support.
- **Bilingual Interface**: Full localization support for English (US) and Traditional Chinese (Taiwan).

---

## 🖥 System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later (fully compatible with macOS 15+ Sequoia)
- **Hardware Architecture**: Universal binary supporting both Apple Silicon (M1/M2/M3/M4) and Intel Macs
- **Required System Permissions**:
  - **Accessibility**: Required to synthesize mouse clicks, position cursor warps, and post scroll wheel events.
  - **Input Monitoring**: Required to read raw IOHID packets from external USB / Type-C touchscreen monitors in the background.

---

## 🚀 Installation & First Launch

### Pre-built Binary Installation

1. Download the latest `macTouchControl.zip` or `.dmg` from [GitHub Releases](https://github.com/leechunyen/macTouchControl/releases).
2. Unpack the archive and drag `macTouchControl.app` into your `/Applications` folder.

---

### ⚠️ Opening the App (Bypassing macOS Gatekeeper)

> [!IMPORTANT]
> **Why does macOS display a warning or say the app is damaged?**
> 
> `macTouchControl` is a free, open-source utility developed independently. Because the developer has not enrolled in the paid Apple Developer Program ($99/year), this binary is **not notarized or signed with an Apple Developer ID certificate**.
> 
> As a result, macOS Gatekeeper automatically attaches a quarantine flag to the downloaded file and may present one of the following prompts upon opening:
> - *“macTouchControl is damaged and can’t be opened. You should move it to the Trash.”*
> - *“macTouchControl cannot be opened because Apple cannot check it for malicious software.”*
> - *“macTouchControl cannot be opened because the developer cannot be verified.”*
> 
> **This is standard macOS security behavior for unsigned open-source applications. The software is completely safe and open-source.** Choose one of the two solutions below to open it:

#### Method 1: Remove the Quarantine Flag via Terminal (Recommended & Fastest)

If macOS reports that the app is "damaged" or refuses to launch it, open the macOS **Terminal** app, paste the following command, and press **Enter**:

```bash
xattr -cr /Applications/macTouchControl.app
```

> **What this command does**: `xattr -cr` recursively strips the `com.apple.quarantine` extended attribute that macOS attaches to internet-downloaded binaries. Once executed, `macTouchControl` will open normally when double-clicked.

---

#### Method 2: Open via macOS System Settings

1. In Finder, navigate to `/Applications`.
2. **Right-click (or Control-click)** on `macTouchControl.app` and choose **Open**.
3. In the dialog that appears, click **Open**.
4. If macOS still blocks launch, open **System Settings > Privacy & Security**.
5. Scroll down to the **Security** section. You will see a notice stating:
   > *“macTouchControl” was blocked from use because it is not from an identified developer.*
6. Click **Open Anyway**, then enter your administrator password or authenticate with Touch ID to proceed.

---

### 🔑 Required System Permissions

`macTouchControl` needs to capture raw USB/HID touchscreen reports and synthesize mouse cursor movements and scrolling. On initial launch, grant the following two permissions:

1. **Accessibility**:
   - Navigate to **System Settings > Privacy & Security > Accessibility** and toggle on `macTouchControl`.
   - *Purpose: Used for cursor coordinate warping, left/right mouse click simulation, window title bar dragging, and 2D scroll injection.*
2. **Input Monitoring**:
   - Navigate to **System Settings > Privacy & Security > Input Monitoring** and toggle on `macTouchControl`.
   - *Purpose: Used for reading raw IOHID touch events dispatched by external touchscreen digitizers.*

> [!TIP]
> **Updating the App**:
> Because the binary is ad-hoc signed, replacing `/Applications/macTouchControl.app` with a newer version may cause macOS to invalidate existing permission grants.
> If touchscreen input stops responding after an update, go to **System Settings > Privacy & Security**, toggle both **Accessibility** and **Input Monitoring** off and back on (or remove them with `-` and re-add them).

---

### Building from Source (Xcode)

If you prefer to build the application locally from source:

1. Clone this repository:
   ```bash
   git clone https://github.com/leechunyen/macTouchControl.git
   cd macTouchControl
   ```

2. Open the project in Xcode:
   ```bash
   open macTouchControl.xcodeproj
   ```

3. Select the **`macTouchControl`** scheme and choose **`My Mac`** as the run destination.
4. Press **`Cmd + B`** to build or **`Cmd + R`** to run.
5. Grant **Accessibility** and **Input Monitoring** permissions when prompted.

### Running the Test Suite

The project includes unit and integration tests using Swift Testing and XCTest:
- In Xcode, press **`Cmd + U`**, or run via terminal:
  ```bash
  xcodebuild test -scheme macTouchControl -destination 'platform=macOS'
  ```

---

## 📖 User Guide

1. **Connect Your Touchscreen**: Connect your external touch monitor to your Mac via USB-C (DisplayPort Alt Mode + Touch data) or HDMI plus a USB-A/C data cable.
2. **Assign the Display**:
   - Open `macTouchControl`.
   - Under the **Touch Panel & Display 1-to-1 Mapping** section, locate your detected touch panel.
   - Click **Identify** to verify the monitor index, then select the target screen from the dropdown menu.
3. **Configure Gestures**:
   - **Touchscreen 2D Scrolling**: Enable for iPad-style drag-to-scroll. Customize speed and natural scroll direction as desired.
   - **Long Press Right-Click**: Enable for Windows/iPad-style contextual menus with visual ring feedback. Adjust the hold duration (0.40s to 1.50s).
   - **Right Edge Swipe**: Enable to swipe open Notification Center from the right bezel.
4. **Close to Menu Bar**:
   - Click the window close button (`x`). The application will tuck cleanly into the macOS menu bar, maintaining active touch mapping in the background.

---

## ☕️ Support & Donation

If you find `macTouchControl` useful and would like to support its ongoing development and maintenance, consider buying me a coffee!

<a href="https://buymeacoffee.com/cylee99" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 48px !important; width: 174px !important;" >
</a>

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). You are free to run, study, share, and modify this software under the terms of the license.
