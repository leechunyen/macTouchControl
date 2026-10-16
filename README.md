# macTouchControl

<p align="center">
  A modern, lightweight macOS utility designed for external touchscreen monitors and digitizers.<br>
  Eliminates cursor-jumping issues across extended displays, brings natural 2D tablet scrolling, Windows/iPad-style long-press right-clicks, and screen edge gestures to Mac.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B-blue.svg" alt="Platform">
  <img src="https://img.shields.io/badge/Language-Swift%205.9%20%2F%20SwiftUI-orange.svg" alt="Language">
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%26%20Intel)-purple.svg" alt="Architecture">
  <img src="https://img.shields.io/badge/License-GPL--3.0-green.svg" alt="License">
  <a href="https://buymeacoffee.com/cylee99"><img src="https://img.shields.io/badge/Buy%20Me%20a%20Coffee-Donate-yellow.svg?logo=buy-me-a-coffee" alt="Buy Me A Coffee"></a>
</p>

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
- **Bilingual Interface**: Full support for English (US) and Traditional Chinese (Taiwan).

---

## 🖥 System Requirements

- **Operating System**: macOS 14.0 (Sonoma) or later (fully compatible with macOS 15+ Sequoia)
- **Hardware Architecture**: Universal binary supporting both Apple Silicon (M1/M2/M3/M4) and Intel Macs
- **Required System Permissions**:
  - **Accessibility**: Required to synthesize mouse clicks, position cursor warps, and post scroll wheel events.
  - **Input Monitoring**: Required to read raw IOHID packets from external USB / Type-C touchscreen monitors in the background.

---

## 🚀 Building & Installation

### Building from Source (Xcode)

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
5. On the first launch, grant **Accessibility** and **Input Monitoring** permissions when prompted in **System Settings > Privacy & Security**.

### Running the Test Suite

The project includes unit and integration tests using Swift Testing and XCTest:
- In Xcode, press **`Cmd + U`**, or run via terminal:
  ```bash
  xcodebuild test -scheme macTouchControl -destination 'platform=macOS'
  ```

---

## 📖 User Guide

1. **Connect Your Touchscreen**: Connect your external touch monitor to your Mac via USB-C (DisplayPort Alt Mode + Touch) or HDMI + USB-A/C data cable.
2. **Assign the Display**:
   - Open `macTouchControl`.
   - In the **Touch Panel & Display 1-to-1 Mapping** section, locate your detected touch panel.
   - Click **Identify** to verify the monitor index, then select the target screen from the dropdown menu.
3. **Configure Gestures**:
   - **Touchscreen 2D Scrolling**: Enable for iPad-style drag-to-scroll. Customize speed and natural scroll direction as desired.
   - **Long Press Right-Click**: Enable for Windows/iPad-style contextual menus with visual ring feedback. Adjust the hold duration (0.40s to 1.50s).
   - **Right Edge Swipe**: Enable to swipe open Notification Center from the right bezel.
4. **Close to Menu Bar**:
   - Click the window close button (`x`). The application will tuck cleanly into the macOS menu bar, maintaining active touch mapping in the background.

---

## ☕️ Support & Donation

If you find `macTouchControl` useful and would like to support its ongoing development and maintenance, you can buy me a coffee!

<p align="center">
  <a href="https://buymeacoffee.com/cylee99" target="_blank">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 50px !important;width: 180px !important;" >
  </a>
</p>

- **Buy Me a Coffee**: [https://buymeacoffee.com/cylee99](https://buymeacoffee.com/cylee99)

Your support is greatly appreciated! ❤️

---

## 📄 License

This project is licensed under the [GNU General Public License v3.0 (GPL-3.0)](LICENSE). You are free to run, study, share, and modify this software under the terms of the license.
