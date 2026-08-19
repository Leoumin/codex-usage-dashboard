# Codex Usage iOS Widget Design

## Goal

Add a personal-use iOS app and WidgetKit extension to the existing Codex usage HUD. The Mac app syncs the current Codex access credential through iCloud Keychain; the iPhone reads it and displays Codex usage, reset credits, and expiry times without a separate server.

## Scope

- Keep the existing macOS floating dashboard and 60-second refresh behavior.
- Sync only `access_token`, `account_id`, and `last_refresh` from `~/.codex/auth.json`.
- Do not sync `refresh_token` in the first version. Codex on the Mac remains responsible for refreshing the session.
- Add an iOS 17+ SwiftUI app with manual refresh and last-updated state.
- Add small and medium widgets for the Home Screen and Today View.
- Do not add login, backend services, analytics, push notifications, or App Store distribution work.

## Architecture

```text
~/.codex/auth.json
        |
        v
macOS CodexUsageHUD
        |
        v
iCloud Keychain (synchronizable credential)
        |
        v
iOS app / Widget timeline provider
        |
        +--> private Codex usage endpoints
        |
        v
App Group cache (usage snapshot only)
```

The Mac and iOS targets use the same Apple Developer Team and Keychain Access Group. The credential is stored as a synchronizable generic-password item with an accessibility class compatible with iCloud sync. Tokens never enter `UserDefaults`, logs, widget configuration, or screenshots.

The iOS app and widget share a small source module containing models, JSON parsing, API fetching, Keychain access, and snapshot caching. The app refreshes immediately when opened or when the user pulls to refresh. When WidgetKit requests a new timeline, the widget may fetch fresh data using the shared Keychain credential; on failure it displays the last cached snapshot.

## Data Flow

1. Every existing Mac refresh reads the current Codex access token.
2. The Mac updates the synchronizable Keychain item only when its payload changed.
3. iCloud Keychain makes the item available to the signed iOS app family.
4. The iOS client calls `/backend-api/wham/usage` and `/backend-api/wham/rate-limit-reset-credits` with the bearer token.
5. Parsed usage data is stored as a Codable snapshot in the App Group container.
6. The app reloads widget timelines after a successful manual refresh.
7. WidgetKit chooses the actual background refresh time; the timeline requests another update after approximately 30 minutes.

## Interface

The iOS app follows the restrained Mac dashboard style: system background, compact usage sections, native progress indicators, reset-credit rows, last-updated time, and one refresh control.

<design_plan>
Python RNG execution for the 99-character native design prompt:
`seed=99`
`hero=Artistic Asymmetry; font=Geist`
`components=Horizontal Accordions, Infinite Marquee, Inline Typography Images; motion=Image Scale & Fade, Scroll Pinning`

Native AIDA mapping: the toolbar replaces web navigation; the asymmetric usage summary provides attention; the gapless metric layout provides interest; reset-expiry detail provides desire; manual refresh is the only action. There is no marketing hero, footer, pricing CTA, or decorative media because this is a compact operational tool.

Typography verification: the app title is constrained to one line and the primary percentage has a fixed metric frame, minimum scale factor, and monospaced digits. Geist is used for display metrics and headings; system text remains the accessibility fallback. There are no stamps, tags, badges, or multi-line hero copy.

Density verification: the app summary is a complete two-column row (`1 + 1 = 2`), followed by full-width usage and reset sections. The medium widget is a complete two-column by two-row layout (`2 x 2 = 4` occupied cells). No spacer creates a dead grid cell. Cards are limited to three visual groups and are never nested.

Native component translation: horizontal accordion becomes a compact expandable reset-expiry ledger in the app; infinite marquee becomes a single clipped, non-repeating status line because continuous motion is inappropriate in WidgetKit; inline typography imagery becomes restrained inline SF Symbols. Image scale/fade becomes a short progress-value transition after refresh; scroll pinning becomes a stable compact summary header. Widgets remain static snapshots as required by WidgetKit.

Label and contrast sweep: no meta labels such as `SECTION 01` or `ABOUT US`; icon-only refresh controls have accessibility labels; all text uses adaptive system foreground colors with WCAG-safe contrast. No purple gradient, decorative orb, stock image, or web-only GSAP/Tailwind code is introduced.
</design_plan>

The selected visual direction is asymmetric but quiet: the primary remaining percentage anchors the upper-left, while weekly allowance and reset count occupy the trailing metric column. Healthy usage uses teal, upcoming limits use amber, and critical remaining usage uses system red against adaptive graphite or system backgrounds. Corners stay at 8 points and spacing follows an 8-point rhythm.

- Small widget: primary remaining percentage, available reset count, and next reset time.
- Medium widget: 5-hour and weekly remaining percentages with progress bars, reset count, and nearest credit expiry.
- Stale cached data remains visible and is marked with its last update time.

## Error Handling

- Missing synchronized credential: show `等待 Mac 同步凭证` and retain cached data.
- HTTP 401/403: show `凭证已过期，请在 Mac 上打开 Codex` and retain cached data.
- Network or private-endpoint failure: show cached data with a stale timestamp.
- Malformed response: reject the new response without overwriting the last valid cache.
- Keychain writes never include token values in errors or logs.

## Verification

- Unit tests cover credential payload coding, usage parsing, reset-credit parsing, cache round trips, and auth-error classification.
- Build the macOS Swift package and run its self-test.
- Build the iOS app and widget for an installed simulator runtime.
- Render small and medium widget previews or simulator screenshots and check text fit.
- Inspect built entitlements and code signatures for the shared Keychain and App Group identifiers.
- Cross-device iCloud Keychain delivery requires a final check on the user's signed Mac and iPhone because the simulator cannot prove real-device synchronization.

## Known Limits

- Codex usage endpoints are private and may change.
- iCloud Keychain and WidgetKit refresh timing have no real-time guarantee.
- If the Mac does not refresh Codex credentials before the access token expires, the iPhone continues showing cached data until the Mac publishes a newer token.
