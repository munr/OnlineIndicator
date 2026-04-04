# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git Workflow

- **Never commit directly to `main`.** Always create a feature branch before starting any work, even small changes.
- Branch naming: `feature/<short-description>` for new features, `fix/<short-description>` for bug fixes.
- Open a pull request to merge into `main`.

## Build & Run

Open `Online Indicator.xcodeproj` in Xcode and use the standard Run/Build commands, or from the command line:

```bash
# Debug build
xcodebuild build \
 -project "Online Indicator.xcodeproj" \
 -scheme "Online Indicator" \
 -configuration Debug

# Release archive (used by CI)
xcodebuild archive \
 -project "Online Indicator.xcodeproj" \
 -scheme "Online Indicator" \
 -configuration Release \
 -archivePath build/OnlineIndicator.xcarchive \
 CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual PROVISIONING_PROFILE_SPECIFIER=""

# Run tests
xcodebuild test \
 -project "Online Indicator.xcodeproj" \
 -scheme "OnlineIndicatorTests"
```

Releases are built automatically by `.github/workflows/build-dmg.yml` on `v*` tags. `MARKETING_VERSION` is injected from the git tag at build time — do not hard-code it.

## Architecture

This is a **menu bar only** SwiftUI + AppKit macOS app (no main window). The entry point is `Online-IndicatorApp.swift`, which defines the `@main` struct `OnlineIndicatorApp` that uses `@NSApplicationDelegateAdaptor(AppDelegate.self)`. `AppDelegate` owns the `NSStatusItem` and wires all handlers.

### Core status flow

```
NetworkMonitor (NWPathMonitor)
 └─► AppState.checkConnection()
 ├─► .noNetwork (if no path)
 └─► ConnectivityChecker.checkOutboundConnection()
 ├─► .connected (HTTP 200–399 + body contains "Success" for captive.apple.com; HTTP 200–399 for custom URLs)
 └─► .blocked (any other result)
 └─► AppDelegate.statusUpdateHandler (all statuses)
 ├─► AppDelegate.applyIcon(for:wifiName:isVPNActive:)
 │ └─► StatusIconRenderer.render(for:wifiName:isVPNActive:)
 └─► MenuBuilder.updateConnectionStatus(_:)
```

`AppState` also owns a `NetworkSpeedMonitor` (download/upload/ping) and tracks `isVPNActive`.
`AppState` owns the timer (default 30 s, configurable) and debounces rapid `NetworkMonitor` path changes (1 s). Settings changes call `AppState.restart()` to reset the timer and probe immediately.

### Menu

The menu is a custom card-style layout built entirely with view-backed `NSMenuItem`s:

1. **Hero header** (`MenuHeroHeaderView`) — shows connection status, WiFi name + RSSI, external IP, ISP, VPN badge
2. **Stats bar** (`MenuStatsBarView`) — ping, download Mbps, upload Mbps; tapping triggers a manual refresh
3. **NETWORK section** — Internal IPv4, Internal IPv6 (static rows, updated via stored `MenuInfoRowView?` references)
4. **ROUTER section** — Gateway (static), DNS entries (dynamic, tag = `dnsTag = 800`)
5. **Footer** (`MenuFooterView`) — Settings and Quit buttons

`MenuBuilder` builds the `NSMenu` once. Static rows are updated via stored view references. DNS uses integer tag `dnsTag = 800` so rows can be removed and re-inserted without rebuilding the full menu. There is no `knownNetworksTag`.

`IPAddressProvider.current()` is called on every connectivity check cycle and on every menu open (`menuWillOpen`).

### External data

`AppDelegate` holds two `CachedFetcher` instances (TTL 60 s):
- `CachedFetcher.externalIP` — fetches public IP from `api.ipify.org`
- `CachedFetcher.isp` — fetches ISP/ASN from `ipinfo.io/org`

Caches are invalidated on WiFi drop or VPN state change.

### VPN detection

`IPAddressProvider.current()` detects active VPN tunnels by scanning for `utun*`/`ipsec*` interfaces that are UP + RUNNING with an IPv4 address. `AppState` tracks `isVPNActive` and fires `vpnStatusChangedHandler` on changes.

### Speed monitoring

`NetworkSpeedMonitor` is owned by `AppState`. Speed tests run against Cloudflare (`__down`/`__up` endpoints). Tests are triggered on app start (after a 5 s delay), on WiFi SSID change, and on explicit user refresh. Ping latency is measured on every connectivity check via the `ConnectivityChecker` elapsed time.

### Icon customisation

`IconPreferences` stores per-status slots (SF Symbol name, color, text label, label-enabled flag) in `UserDefaults` under composite keys like `iconSymbol.connected`. Keys are built from registered prefixes in `UserDefaultsKeys.swift` plus a per-status suffix (`connected`, `blocked`, `noNetwork`).

`StatusIconRenderer.render(for:wifiName:isVPNActive:)` is stateless — it reads `IconPreferences` and returns an `Output` with a tinted `NSImage` (and an optional `NSAttributedString` for text-label mode), a tooltip, and an accessibility label. When `isVPNActive` is true, a `lock.shield.fill` badge is composited onto the icon. `AppDelegate.applyIcon` consumes this output and sets it on the `NSStatusItem.button`.

### Settings & persistence

All `UserDefaults` keys are defined in `UserDefaultsKeys.swift` as `UserDefaults.Key` enum cases — always add new keys there. Settings UI is in `SettingsView.swift` and uses `SettingsSection` / `SettingsRow` components throughout; follow that pattern for new settings.

`WindowCoordinator` manages opening/closing the Settings and Onboarding windows (both `NSWindow`-backed SwiftUI). The app uses Sparkle for auto-updates; `WindowCoordinator` holds a callback wired to `SPUStandardUpdaterController`.

### Key files

| File | Purpose |
|------|---------|
| `AppState.swift` | Single source of truth for `ConnectionStatus`; owns timer, speed monitor, VPN state, and monitoring |
| `ConnectivityChecker.swift` | HTTP probe to `captive.apple.com` (or custom URL); returns reachability + latency |
| `NetworkSpeedMonitor.swift` | Measures download/upload Mbps and ping; triggered explicitly, no background timer |
| `CachedFetcher.swift` | Generic TTL-cached URL fetcher; shared instances for external IP and ISP |
| `MenuBuilder.swift` | Builds and dynamically updates the `NSMenu` with view-backed items |
| `StatusIconRenderer.swift` | Stateless icon rendering from preferences; supports VPN badge overlay |
| `IconPreferences.swift` | Read/write per-status icon slots; posts `iconPreferencesChanged` notification |
| `IPAddressProvider.swift` | Reads live IPv4/IPv6/gateway/DNS/WiFi name+RSSI/VPN state |
| `UserDefaultsKeys.swift` | Central registry of all `UserDefaults` keys |
| `WindowCoordinator.swift` | Manages Settings and Onboarding `NSWindow` lifecycle |
