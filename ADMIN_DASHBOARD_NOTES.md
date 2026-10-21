OS Dating Admin Dashboard Update

The Flutter admin dashboard has been expanded with:
- Overview metrics and quick actions
- Verification queue and review navigation
- Member search and account suspension
- Safety/report queue and moderation action
- Compose direct admin messages and broadcast messages
- Compose app-wide announcements

Backend integration note:
The source archive contains the Flutter client only; it does not contain the API server. The following authenticated admin endpoints must exist server-side for all new controls to work:
- GET /admin/users?search=<query> -> list of users, each with id/user_id, display_name/name, email and optional is_suspended/status
- POST /admin/messages -> {subject, body, recipient_type: "all"|"user", recipient_user_id?}
- POST /admin/announcements -> {title, body, audience: "all"}
Existing API endpoints used by the page include GET /admin/dashboard, GET /admin/reports, POST /admin/verifications/{id}/review and POST /admin/users/{id}/suspend.

The server must enforce admin authorization on every admin endpoint. Hiding the tab in Flutter is not a security boundary. A missing endpoint will display the server error in the app; the client will not report success unless the API request succeeds.

Additional member/admin tools in this revision:
- Member rows expose real chat, audio-call, and video-call actions. They use the existing POST /conversations/open/{userId} and /calls/invite flows. The server may deny opening a conversation or calling if its connection/permission rules do not allow it; the UI surfaces that error.
- Member list filters use is_verified, verified, or verification_status == "verified"; server responses should provide a consistent verification field.
- The admin header lets the signed-in admin change their own profile photo using the existing upload endpoint and PATCH /me/profile flow.
- Admin identity is loaded from GET /me. Profile upload uses the same existing upload implementation as member profiles.

For accurate counts and verified/unverified filters, GET /admin/dashboard should return total_users, verified_users, pending, open_reports, suspended_users, and new_users_today in counts, and GET /admin/users should return verification status per user. Chat/calls still depend on backend authorization and conversation/call policies.
