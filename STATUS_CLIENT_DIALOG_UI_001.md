# VOSTOK CLIENT V2 — DIALOG UI 001

## Base
- Exact current Azure Mobile source supplied by user as `Java1.zip` + `Java2.zip`.
- Application/package: `ru.azure.games`.
- Old VOSTOK launcher/client repository is NOT the source base for this Candidate.
- Current work branch: `client-v2-dialog-ui-001`.

## Exact dialog implementation found
- `app/src/main/java/ru/azure/games/gui/dialogs/Dialog.java`
- `app/src/main/java/ru/azure/games/gui/dialogs/DialogAdapter.java`
- `app/src/main/res/layout/dialog_old.xml`
- `app/src/main/res/layout/dialog_item_old.xml`

## Goal
All standard server SA-MP dialogs use one VOSTOK visual language based on the supplied "Панель лидера" reference:
- dark rounded centered modal;
- clean title/content/list geometry;
- VOSTOK orange primary action (#FF6B2C);
- dark secondary action;
- orange narrow scrollbar;
- no Azure blue gradient/blob;
- stable aligned rows for lists and tablists.

## Candidate changes prepared against the exact Azure source
1. Replaced active `dialog_old.xml` shell while preserving the existing view IDs and server response contract.
2. Reworked `dialog_item_old.xml` to fixed full-width rows.
3. Added VOSTOK dialog drawables with primary orange `#FF6B2C`.
4. Removed active dependence on donor blue dialog background/scrollbar/button assets.
5. Fixed RecyclerView recycled-column bleed: all row fields are reset before binding.
6. Fixed donor ViewHolder bug that skipped `item_field1`, which shifted simple LIST rows and TABLIST columns.
7. TABLIST header row is now explicitly shown only for `DIALOG_STYLE_TABLIST_HEADER`.
8. Input/list/msgbox remain routed through the same central `Dialog.java`.

## Local static gate
PASS:
- all modified/new XML parses;
- all referenced dimen resources exist;
- Java brace balance;
- no donor blue constants in active VOSTOK dialog resources.

## Build/device promotion gate
Still required:
- exact Azure source imported into this GitHub repo;
- JNI + Android GitHub Actions build PASS;
- device smoke: LIST, long LIST, TABLIST, TABLIST_HEADERS, MSGBOX, INPUT, PASSWORD;
- repeated `Пусто` inventory list;
- documents/licenses dialog;
- one-button and two-button dialogs.

## Status
CURRENT CLIENT CANDIDATE — DIALOG_UI_001
Promotion: NOT YET.
