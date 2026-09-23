# VOSTOK CLIENT V2 — DIALOG UI 001

## Base
- New client base supplied as `Java1.zip` + `Java2.zip`.
- This branch is the first VOSTOK client-v2 UI Candidate.
- Old VOSTOK client repo is not the base for this branch.

## Goal
Unify all SA-MP dialogs to the visual language of the supplied "Панель лидера" reference:
- dark rounded modal card;
- clean title and content spacing;
- consistent list rows;
- fixed dialog geometry (no wrap-content jumping);
- VOSTOK orange primary action;
- dark secondary action;
- orange scrollbar;
- no Azure/BR blue blob/gradient;
- cleaner modal dim background;
- stable list width for repeated "Пусто" rows and tablists.

## Implemented in patcher
`tools/apply_vostok_dialog_ui.py`:
- auto-detects current `dialog.xml`, `dialog_item.xml`, `DialogManager.java`, `DialogAdapter.java`;
- preserves the current CustomRecyclerView class name;
- replaces donor dialog surface with VOSTOK resources;
- fixes `loadSizes()` so server text does not resize/collapse the dialog;
- forces list rows to match the dialog card width;
- removes donor blue scrollbar/gradient from the dialog surface.

## VOSTOK accent
Primary action: `#F2642D`.

## Gate
1. Patch script syntax check — GitHub Actions.
2. Import exact Azure client source.
3. Apply patch against source.
4. Full Android/JNI build in GitHub Actions.
5. Device smoke:
   - list dialog;
   - long list with scrollbar;
   - TABLIST/TABLIST_HEADERS;
   - MSGBOX;
   - INPUT/PASSWORD;
   - one-button and two-button dialogs;
   - repeated "Пусто" inventory rows;
   - documents/licenses dialog.
6. Only after device PASS can this become client MASTER.

## Status
CURRENT CANDIDATE — DIALOG_UI_001
Promotion: NOT YET.
