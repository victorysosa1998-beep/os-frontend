OS UI overhaul (merge into the existing Flutter project, keep your android/ and ios/ folders)

NEW FILES
  lib/theme/os_cartoon.dart        Animated cartoon dating scenes (drawn in code: no real photos, no downloads)
  lib/theme/os_dialogs.dart        OsPopup, osConfirm, osInfo, incoming-call popup
  lib/theme/os_layout.dart         Breakpoints, ResponsiveBody, app-wide frame (text-scale clamp + max width)
  lib/screens/features_hub_screen.dart   "Features" tab: every feature one tap away

CHANGED
  onboarding_screen.dart   4 cartoon slides, landscape/tablet layout (Unsplash photos removed)
  call_screen.dart         New UI + immediate hang-up (see below)
  app_shell.dart           Tabs: Feed | Discover | Chats | Features | You. Verify banner for unverified members.
                           NavigationRail on wide screens. Styled reveal/call popups. Adaptive grids.
                           Admin photo never blurred/protected.
  settings_screen.dart     Responsive, styled sign-out/delete popups, shared info pages
  admin_screen.dart        Bottom bar (phone) / side rail (wide), badges, adaptive stat + tool grids
  chat_screen.dart         Width-capped on wide screens
  main.dart, app_theme.dart  Global responsive frame, themed dialogs

CALL HANG-UP
  End / back / swipe-down: screen closes instantly, mic+camera stop, media room disconnects,
  server is told (retries up to 5x). If the other person leaves, your side ends immediately too.
  Backend now also deletes the LiveKit room on /calls/{id}/end so nobody can stay connected.

ADMIN PHOTO RULES
  Members always see the admin photo unblurred; admin always sees member photos unblurred.
  Enforced on the backend (blurred-profile-url, download-url, reveal status, reveal-request) and in the UI.

RUN
  flutter pub get
  dart format lib
  flutter analyze
  flutter build apk --debug
(Requires Flutter 3.27+, same as your existing code that uses Color.withValues.)
