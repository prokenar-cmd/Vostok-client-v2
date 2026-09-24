# VOSTOK CLIENT RUNTIME FIX 006

Apply to the already working local client source:
`C:\Users\user\Desktop\client_src`

This patch is stacked on the user's runtime-passed 005A source and preserves:
- btn_phone as View (the crash fix);
- Dialog UI;
- current VOSTOK HUD;
- phone/work;
- full-screen menu/inventory;
- UI layering.

Changes:
- HUD Editor: position + per-block scale (55%..140%, 5% steps), persistent.
- Phone Work: narrow-screen order cards, no letter-by-letter wrapping; phone content area widened.
- Inventory: only real server slots 1..20; removes locked 21..30 section; 4-column grid with vertical scroll; new neutral silhouette.

Run:
`0_APPLY_CLIENT_FIX_006.cmd`

The script creates a source backup before changes. Rebuild APK in Android Studio after PASS.
