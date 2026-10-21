OS UI pass 3 (merge into your Flutter project; keep android/ and ios/)

NEW FILES (lib/theme)
  os_buttons.dart   OsButton (primary/secondary/outline/danger/ghost), OsIconBtn, OsPill, OsPressable
  os_chrome.dart    OsScreenHeader, OsSectionTitle, OsFloatingNavBar, OsGetStartedCard
  os_tips.dart      Recurring animated feature pop-ups (8 tips, cartoon scenes, floating chips)

CHANGED
  app_theme.dart      Rounder, glowing buttons; switch, slider, checkbox, popup menu, FAB themes (every button app-wide)
  os_ui.dart          OsGradientButton now uses OsButton (same API)
  app_shell.dart      Floating animated bottom nav, styled headers on Feed / Discover / Chats / You,
                      "Get started" flow card, Feed filter pills, new Search / Nearby / Accept / Save buttons,
                      prettier empty states, chat rows as cards, tip pop-up timer
  auth_screen.dart    Illustrated hero, Sign in / Join OS switch, glass form card, fingerprint button, trust row
  settings_screen.dart  "Feature tips" on/off switch

POP-UPS
  First-run tour still shows first. After that one tip appears every 25 minutes of use (45s check),
  only when nothing else is open (no call, chat page, or other popup). Buttons: action / Maybe later / Stop tips.
  Turn back on: Settings > Feature tips.

NOT TOUCHED: API calls, state, validators, call/chat logic, backend.

RUN
  flutter pub get
  dart format lib
  flutter analyze
  flutter run
