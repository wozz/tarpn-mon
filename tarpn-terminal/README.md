# TARPN Monitor - Mobile & Web App

This directory contains the universal React Native (Expo) application for the TARPN Monitor.

## Prerequisites

1.  **Node.js**: Install standard Node.js (LTS recommended).
2.  **Expo Go**:
    *   **Android:** Install "Expo Go" from the Google Play Store.
    *   **iOS:** Install "Expo Go" from the Apple App Store.
3.  **Backend**: The Go backend (`main.go`) must be running to provide the WebSocket API.

---

## 1. Start the Backend

The app relies on the TARPN Go backend for data.

```bash
# In the project root (../)
go run main.go
```
*By default, this runs on port `8212`.*

---

## 2. Running the App

Navigate to the app directory:
```bash
cd tarpn-app
```

### A. Web Version (Browser)

This runs the app as a standard website (Single Page Application).

```bash
npx expo start --web
```
*   Press `w` in the terminal to open the browser.
*   **Note:** If running locally, ensure the Go backend allows CORS or is served on `localhost`.

### B. Android (Physical Device)

1.  Ensure your phone and computer are on the **same Wi-Fi network**.
2.  Run the development server:
    ```bash
    npx expo start
    ```
3.  Open **Expo Go** on your Android phone.
4.  Scan the QR code displayed in the terminal.
5.  **Important:** In the app, tap **⚙️ Settings** and change the **Host** to your computer's local IP address (e.g., `192.168.1.50`). *`localhost` on the phone refers to the phone itself, not your PC.*

### C. Android (Emulator)

1.  Set up an Android Emulator via Android Studio.
2.  Run the app:
    ```bash
    npx expo start --android
    ```
3.  **Important:** The default host `10.0.2.2` is correctly configured to point to your computer's `localhost` from within the emulator.

### D. iOS (iPhone/iPad)

*   **Physical Device:** Same steps as Android (scan QR code with Camera app or Expo Go).
*   **Simulator:** Requires a Mac with Xcode. Run `npx expo start --ios`.

---

## 3. Configuration

The app includes a **Settings** menu (gear icon) to configure:

*   **Host IP**: The IP address of the machine running `main.go`.
*   **Port**: The WebSocket port (default `8212`).
*   **Auto-scroll**: Enable/Disable automatic scrolling for new logs.
*   **Filters**: Hiding specific TNC routes.

---

## 4. Building for Production

### Web Build
To generate a static folder (`web-build`) that you can serve with Nginx, Apache, or embed in the Go app:

```bash
npx expo export -p web
```

### Android APK (Standard)
To build a standalone APK file that can be installed without Expo Go:

1.  Install EAS CLI: `npm install -g eas-cli`
2.  Login: `eas login`
3.  Configure: `eas build:configure`
4.  Build:
    ```bash
    eas build -p android --profile preview
    ```
