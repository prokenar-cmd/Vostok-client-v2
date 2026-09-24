$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$root = Join-Path $env:USERPROFILE "Desktop\client_src"
if (!(Test-Path (Join-Path $root "app\src\main"))) {
    throw "VOSTOK: client_src not found at $root"
}

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = Join-Path $root "VOSTOK_BACKUPS\RUNTIME_FIX_006_$stamp"
New-Item -ItemType Directory -Force -Path $backup | Out-Null

$javaGui = Join-Path $root "app\src\main\java\ru\azure\games\gui"
$res = Join-Path $root "app\src\main\res"
$nl = [Environment]::NewLine

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path $Path
    if ($dir -and !(Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

function Backup-File([string]$Path) {
    if (!(Test-Path $Path)) { return }
    $rel = $Path.Substring($root.Length).TrimStart('\')
    $dst = Join-Path $backup $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $dst -Force
}

function Replace-JavaMethod([string]$Text, [string]$SignatureRegex, [string]$Replacement) {
    $m = [regex]::Match($Text, $SignatureRegex, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (!$m.Success) { throw "VOSTOK: Java method not found: $SignatureRegex" }
    $open = $Text.IndexOf('{', $m.Index + $m.Length)
    if ($open -lt 0) { throw "VOSTOK: method opening brace not found" }

    $depth = 0
    $inString = $false
    $inChar = $false
    $escaped = $false
    $inLineComment = $false
    $inBlockComment = $false
    $close = -1

    for ($i = $open; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $n = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

        if ($inLineComment) {
            if ([int][char]$c -eq 10) { $inLineComment = $false }
            continue
        }
        if ($inBlockComment) {
            if ($c -eq '*' -and $n -eq '/') { $inBlockComment = $false; $i++ }
            continue
        }
        if ($inString) {
            if ($escaped) { $escaped = $false; continue }
            if ($c -eq '\') { $escaped = $true; continue }
            if ($c -eq '"') { $inString = $false }
            continue
        }
        if ($inChar) {
            if ($escaped) { $escaped = $false; continue }
            if ($c -eq '\') { $escaped = $true; continue }
            if ($c -eq "'") { $inChar = $false }
            continue
        }

        if ($c -eq '/' -and $n -eq '/') { $inLineComment = $true; $i++; continue }
        if ($c -eq '/' -and $n -eq '*') { $inBlockComment = $true; $i++; continue }
        if ($c -eq '"') { $inString = $true; continue }
        if ($c -eq "'") { $inChar = $true; continue }

        if ($c -eq '{') { $depth++ }
        elseif ($c -eq '}') {
            $depth--
            if ($depth -eq 0) { $close = $i; break }
        }
    }
    if ($close -lt 0) { throw "VOSTOK: method closing brace not found" }
    return $Text.Substring(0, $m.Index) + $Replacement + $Text.Substring($close + 1)
}

Write-Host "=== VOSTOK CLIENT RUNTIME FIX 006 ==="

# Preserve confirmed FIX 005A.
$hudPath = Join-Path $javaGui "HudManager.java"
if (!(Test-Path $hudPath)) { throw "HudManager.java not found" }
Backup-File $hudPath
$hud = Get-Content -LiteralPath $hudPath -Raw -Encoding UTF8

$groupDecl = 'public\s+ImageView\s+hud_weapon\s*,\s*pass\s*,\s*closehud\s*,\s*btn_phone\s*,\s*btn_shop\s*;'
if ($hud -match $groupDecl) {
    $hud = [regex]::Replace(
        $hud,
        $groupDecl,
        "public ImageView hud_weapon, pass, closehud, btn_shop;" + $nl + "    public View btn_phone;",
        1
    )
}
$hud = $hud -replace '\bImageView\s+btn_phone\b', 'View btn_phone'

if ($hud -notmatch 'import\s+android\.view\.View\s*;') {
    $hud = [regex]::Replace(
        $hud,
        '(package\s+ru\.azure\.games\.gui\s*;\s*)',
        { param($m) $m.Groups[1].Value + $nl + "import android.view.View;" + $nl },
        1
    )
}
Write-Utf8NoBom $hudPath $hud

# HUD editor v2: drag + per-block scale.
$editorPath = Join-Path $javaGui "VostokHudEditor.java"
Backup-File $editorPath
$editorJava = @'
package ru.azure.games.gui;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.drawable.GradientDrawable;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.TextView;

import java.util.LinkedHashMap;
import java.util.Map;

public final class VostokHudEditor {
    private static final String PREFS = "vostok_hud_editor_v2";
    private static final float MIN_SCALE = 0.55f;
    private static final float MAX_SCALE = 1.40f;
    private static final float SCALE_STEP = 0.05f;

    private final Activity activity;
    private final SharedPreferences prefs;
    private final LinkedHashMap<String, View> targets = new LinkedHashMap<>();

    private boolean editing;
    private View selected;
    private String selectedKey;
    private ViewGroup overlay;
    private TextView selectedLabel;
    private TextView scaleLabel;

    private float downRawX;
    private float downRawY;
    private float downX;
    private float downY;

    public VostokHudEditor(Activity activity) {
        this.activity = activity;
        this.prefs = activity.getSharedPreferences(PREFS, Activity.MODE_PRIVATE);
        collectTargets();
        applySaved();

        View menu = byName("btn_vostok_menu");
        if (menu != null) {
            menu.setOnLongClickListener(v -> {
                openEditor();
                return true;
            });
        }
    }

    private View byName(String name) {
        int id = activity.getResources().getIdentifier(name, "id", activity.getPackageName());
        return id == 0 ? null : activity.findViewById(id);
    }

    private View firstByNames(String... names) {
        for (String name : names) {
            View v = byName(name);
            if (v != null) return v;
        }
        return null;
    }

    private View ancestor(View view, int count) {
        View current = view;
        for (int i = 0; i < count && current != null; i++) {
            if (!(current.getParent() instanceof View)) break;
            View next = (View) current.getParent();
            if (next.getId() == android.R.id.content) break;
            current = next;
        }
        return current;
    }

    private void addTarget(String key, View view) {
        if (view == null || targets.containsValue(view)) return;
        targets.put(key, view);
        view.setOnTouchListener((v, event) -> onTargetTouch(key, v, event));
    }

    private void collectTargets() {
        targets.clear();
        addTarget("menu", byName("btn_vostok_menu"));
        addTarget("inventory", byName("btn_vostok_inventory"));
        addTarget("phone", byName("btn_phone"));
        addTarget("gps", byName("btn_vostok_gps"));

        View hp = byName("vostok_hp_text");
        View stats = firstByNames(
                "vostok_status_panel", "vostok_stats_panel",
                "vostok_status_container", "hud_status_panel");
        if (stats == null && hp != null) stats = ancestor(hp, 2);
        addTarget("status", stats);

        View moneyText = firstByNames("money_text", "hud_money");
        View money = firstByNames(
                "vostok_money_panel", "money_panel",
                "hud_money_panel", "money_layout");
        if (money == null && moneyText != null) money = ancestor(moneyText, 1);
        addTarget("money", money);

        View radar = firstByNames(
                "vostok_radar", "hud_radar", "radar_layout",
                "radar_container", "radar_main", "radar");
        addTarget("radar", radar);
    }

    private boolean onTargetTouch(String key, View view, MotionEvent event) {
        if (!editing) return false;

        switch (event.getActionMasked()) {
            case MotionEvent.ACTION_DOWN:
                select(key, view);
                downRawX = event.getRawX();
                downRawY = event.getRawY();
                downX = view.getX();
                downY = view.getY();
                return true;

            case MotionEvent.ACTION_MOVE:
                view.setX(downX + event.getRawX() - downRawX);
                view.setY(downY + event.getRawY() - downRawY);
                return true;

            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                saveOne(key, view);
                return true;
        }
        return true;
    }

    private void select(String key, View view) {
        selectedKey = key;
        selected = view;
        if (selectedLabel != null) selectedLabel.setText("Блок: " + labelFor(key));
        updateScaleLabel();
    }

    private String labelFor(String key) {
        switch (key) {
            case "menu": return "Меню";
            case "inventory": return "Инвентарь";
            case "phone": return "Телефон";
            case "gps": return "GPS";
            case "status": return "HP / броня / сытость";
            case "money": return "Деньги";
            case "radar": return "Радар";
            default: return key;
        }
    }

    private void openEditor() {
        if (editing) return;
        editing = true;
        collectTargets();
        applySaved();

        ViewGroup content = activity.findViewById(android.R.id.content);
        if (content == null) return;

        LinearLayout panel = new LinearLayout(activity);
        panel.setOrientation(LinearLayout.HORIZONTAL);
        panel.setGravity(Gravity.CENTER_VERTICAL);
        panel.setPadding(dp(8), dp(5), dp(8), dp(5));

        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xEE16191F);
        bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1), 0x88FF8A2B);
        panel.setBackground(bg);

        selectedLabel = text("Выберите блок", 12, Color.WHITE);
        panel.addView(selectedLabel, new LinearLayout.LayoutParams(dp(190), dp(38)));

        Button minus = button("−");
        Button plus = button("+");
        scaleLabel = text("100%", 12, 0xFFFF8A2B);
        scaleLabel.setGravity(Gravity.CENTER);

        panel.addView(minus, new LinearLayout.LayoutParams(dp(42), dp(38)));
        panel.addView(scaleLabel, new LinearLayout.LayoutParams(dp(62), dp(38)));
        panel.addView(plus, new LinearLayout.LayoutParams(dp(42), dp(38)));

        Button reset = button("СБРОС");
        Button done = button("ГОТОВО");
        panel.addView(reset, new LinearLayout.LayoutParams(dp(88), dp(38)));
        panel.addView(done, new LinearLayout.LayoutParams(dp(88), dp(38)));

        minus.setOnClickListener(v -> changeScale(-SCALE_STEP));
        plus.setOnClickListener(v -> changeScale(SCALE_STEP));
        reset.setOnClickListener(v -> resetScaleOnly());
        done.setOnClickListener(v -> closeEditor());

        FrameLayout host = new FrameLayout(activity);
        host.setClickable(false);
        host.addView(panel, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.TOP | Gravity.CENTER_HORIZONTAL));

        content.addView(host, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        panel.setClickable(true);
        overlay = host;

        if (!targets.isEmpty()) {
            Map.Entry<String, View> first = targets.entrySet().iterator().next();
            select(first.getKey(), first.getValue());
        }
    }

    private void closeEditor() {
        saveAll();
        editing = false;
        if (overlay != null && overlay.getParent() instanceof ViewGroup) {
            ((ViewGroup) overlay.getParent()).removeView(overlay);
        }
        overlay = null;
        selected = null;
        selectedKey = null;
    }

    private void changeScale(float delta) {
        if (selected == null || selectedKey == null) return;
        float scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, selected.getScaleX() + delta));
        selected.setPivotX(selected.getWidth() / 2f);
        selected.setPivotY(selected.getHeight() / 2f);
        selected.setScaleX(scale);
        selected.setScaleY(scale);
        saveOne(selectedKey, selected);
        updateScaleLabel();
    }

    private void updateScaleLabel() {
        if (scaleLabel == null) return;
        int pct = selected == null ? 100 : Math.round(selected.getScaleX() * 100f);
        scaleLabel.setText(pct + "%");
    }

    private void saveOne(String key, View view) {
        prefs.edit()
                .putFloat(key + "_x", view.getX())
                .putFloat(key + "_y", view.getY())
                .putFloat(key + "_scale", view.getScaleX())
                .apply();
    }

    private void saveAll() {
        for (Map.Entry<String, View> e : targets.entrySet()) {
            saveOne(e.getKey(), e.getValue());
        }
    }

    private void applySaved() {
        for (Map.Entry<String, View> e : targets.entrySet()) {
            String key = e.getKey();
            View view = e.getValue();

            if (prefs.contains(key + "_x")) view.setX(prefs.getFloat(key + "_x", view.getX()));
            if (prefs.contains(key + "_y")) view.setY(prefs.getFloat(key + "_y", view.getY()));

            float scale = prefs.getFloat(key + "_scale", 1.0f);
            scale = Math.max(MIN_SCALE, Math.min(MAX_SCALE, scale));
            view.setScaleX(scale);
            view.setScaleY(scale);
        }
    }

    private void resetScaleOnly() {
        if (selected == null || selectedKey == null) return;
        selected.setScaleX(1f);
        selected.setScaleY(1f);
        saveOne(selectedKey, selected);
        updateScaleLabel();
    }

    private TextView text(String value, int sp, int color) {
        TextView t = new TextView(activity);
        t.setText(value);
        t.setTextColor(color);
        t.setTextSize(sp);
        t.setGravity(Gravity.CENTER_VERTICAL);
        return t;
    }

    private Button button(String value) {
        Button b = new Button(activity);
        b.setText(value);
        b.setTextColor(Color.WHITE);
        b.setTextSize(10);
        b.setAllCaps(false);
        b.setBackgroundColor(0x00222222);
        return b;
    }

    private int dp(float value) {
        return Math.round(value * activity.getResources().getDisplayMetrics().density);
    }
}
'@
Write-Utf8NoBom $editorPath $editorJava

# Phone work order cards.
$phonePath = Join-Path $javaGui "Phone.java"
if (Test-Path $phonePath) {
    Backup-File $phonePath
    $phone = Get-Content -LiteralPath $phonePath -Raw -Encoding UTF8

    $showOrders = @'
    private void showOrders(String rawContent) {
        showWorkShell("Работа");
        addServiceCard("Курьерская служба", "● Вы на смене", 0xFF53C878);

        String content = stripColors(rawContent);
        String[] rows = content.split("\\n");
        ArrayList<String> realRows = new ArrayList<>();
        for (String row : rows) {
            if (row != null && !row.trim().isEmpty()) realRows.add(row.trim());
        }

        if (realRows.isEmpty()) {
            showWorkMessage("Курьерская служба", "Нет заказов", "Сейчас доступных заказов нет.");
            return;
        }

        for (int i = 0; i < realRows.size(); i++) {
            String row = realRows.get(i);
            Matcher matcher = ORDER_PATTERN.matcher(row);

            String orderId = "—";
            String distance = "";
            String reward = "";
            String cargo = row;

            if (matcher.find()) {
                orderId = matcher.group(1);
                distance = matcher.group(2) + " м";
                reward = matcher.group(3) + " ₽";
                cargo = matcher.group(4).trim();
            }

            final int listItem = i;
            LinearLayout card = makeCard(true);
            card.setPadding(dp(10), dp(9), dp(10), dp(9));

            LinearLayout header = new LinearLayout(activity);
            header.setOrientation(LinearLayout.HORIZONTAL);
            header.setGravity(Gravity.CENTER_VERTICAL);

            ImageView icon = new ImageView(activity);
            icon.setImageResource(R.drawable.vostok_phone_box);
            LinearLayout.LayoutParams iconLp = new LinearLayout.LayoutParams(dp(21), dp(21));
            iconLp.setMargins(0, 0, dp(7), 0);
            header.addView(icon, iconLp);

            TextView title = makeText("Заказ #" + orderId, 9, Color.WHITE, true);
            title.setSingleLine(true);
            header.addView(title, new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            TextView arrow = makeText("›", 17, 0xFFFF8A2B, false);
            arrow.setGravity(Gravity.CENTER);
            header.addView(arrow, new LinearLayout.LayoutParams(dp(14), dp(24)));

            card.addView(header);

            TextView cargoText = makeText(cargo, 7, 0xFFB7BBC5, false);
            cargoText.setPadding(dp(28), dp(3), 0, dp(5));
            cargoText.setMaxLines(2);
            card.addView(cargoText);

            LinearLayout footer = new LinearLayout(activity);
            footer.setOrientation(LinearLayout.HORIZONTAL);
            footer.setGravity(Gravity.CENTER_VERTICAL);
            footer.setPadding(dp(28), 0, 0, 0);

            TextView distText = makeText(distance, 7, 0xFF9CA1AA, false);
            footer.addView(distText, new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));

            TextView rewardText = makeText(reward, 8, 0xFFFF8A2B, true);
            rewardText.setGravity(Gravity.END);
            footer.addView(rewardText, new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT));

            card.addView(footer);
            card.setOnClickListener(v -> {
                v.startAnimation(AnimationUtils.loadAnimation(activity, R.anim.button_click));
                acceptOrder(listItem);
            });
            addCardToContent(card);
        }
    }
'@
    $phone = Replace-JavaMethod $phone 'private\s+void\s+showOrders\s*\(\s*String\s+rawContent\s*\)' $showOrders
    Write-Utf8NoBom $phonePath $phone
}

$phoneXml = Join-Path $res "layout\phone.xml"
if (Test-Path $phoneXml) {
    Backup-File $phoneXml
    $xml = Get-Content -LiteralPath $phoneXml -Raw -Encoding UTF8
    $xml = [regex]::Replace(
        $xml,
        '(?s)(android:id="@\+id/phone_screen".{0,400}?android:layout_width=")\d+dp(")',
        '1156dp$2',
        1)
    $xml = [regex]::Replace(
        $xml,
        '(?s)(android:id="@\+id/phone_screen".{0,500}?android:layout_height=")\d+dp(")',
        '1270dp$2',
        1)
    Write-Utf8NoBom $phoneXml $xml
}

# Inventory runtime repair helper.
$invHelperPath = Join-Path $javaGui "VostokInventoryRuntime006.java"
Backup-File $invHelperPath
$invJava = @'
package ru.azure.games.gui;

import android.app.Activity;
import android.graphics.drawable.Drawable;
import android.view.View;
import android.view.ViewGroup;
import android.widget.GridLayout;
import android.widget.ImageView;
import android.widget.ScrollView;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.List;

public final class VostokInventoryRuntime006 {
    private VostokInventoryRuntime006() {}

    public static void apply(Activity activity) {
        if (activity == null) return;
        View root = activity.findViewById(android.R.id.content);
        if (!(root instanceof ViewGroup)) return;

        ViewGroup groupRoot = (ViewGroup) root;
        hideExtraSection(groupRoot);

        GridLayout mainGrid = findLargestGrid(groupRoot);
        if (mainGrid != null) {
            mainGrid.setColumnCount(4);
            for (int i = 0; i < mainGrid.getChildCount(); i++) {
                mainGrid.getChildAt(i).setVisibility(i < 20 ? View.VISIBLE : View.GONE);
            }
            wrapInScroll(mainGrid);
        }

        installSilhouette(activity, groupRoot);
    }

    private static void hideExtraSection(ViewGroup root) {
        List<TextView> texts = new ArrayList<>();
        collectTextViews(root, texts);

        for (TextView tv : texts) {
            CharSequence value = tv.getText();
            if (value == null) continue;
            String s = value.toString().trim().toLowerCase();
            if (s.contains("дополнительные ячейки")) {
                tv.setVisibility(View.GONE);

                if (tv.getParent() instanceof ViewGroup) {
                    ViewGroup parent = (ViewGroup) tv.getParent();
                    int index = parent.indexOfChild(tv);
                    if (index >= 0 && index + 1 < parent.getChildCount()) {
                        View next = parent.getChildAt(index + 1);
                        if (next instanceof GridLayout || idName(next).contains("extra") || idName(next).contains("locked")) {
                            next.setVisibility(View.GONE);
                        }
                    }
                }
            }
        }

        hideNamed(root, "extra");
        hideNamed(root, "locked");
    }

    private static void hideNamed(View view, String token) {
        if (view == null) return;
        String name = idName(view);
        if (!name.isEmpty() && name.contains(token)
                && (name.contains("slot") || name.contains("inventory"))) {
            view.setVisibility(View.GONE);
        }

        if (view instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) view;
            for (int i = 0; i < vg.getChildCount(); i++) hideNamed(vg.getChildAt(i), token);
        }
    }

    private static void collectTextViews(View view, List<TextView> out) {
        if (view instanceof TextView) out.add((TextView) view);
        if (view instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) view;
            for (int i = 0; i < vg.getChildCount(); i++) collectTextViews(vg.getChildAt(i), out);
        }
    }

    private static GridLayout findLargestGrid(View view) {
        GridLayout best = view instanceof GridLayout ? (GridLayout) view : null;
        if (view instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) view;
            for (int i = 0; i < vg.getChildCount(); i++) {
                GridLayout candidate = findLargestGrid(vg.getChildAt(i));
                if (candidate != null && (best == null || candidate.getChildCount() > best.getChildCount())) {
                    best = candidate;
                }
            }
        }
        return best;
    }

    private static void wrapInScroll(GridLayout grid) {
        if (!(grid.getParent() instanceof ViewGroup)) return;
        if (grid.getParent() instanceof ScrollView) return;

        ViewGroup parent = (ViewGroup) grid.getParent();
        int index = parent.indexOfChild(grid);
        if (index < 0) return;

        ViewGroup.LayoutParams original = grid.getLayoutParams();
        parent.removeViewAt(index);

        ScrollView scroll = new ScrollView(grid.getContext());
        scroll.setFillViewport(false);
        scroll.setVerticalScrollBarEnabled(false);
        scroll.setOverScrollMode(View.OVER_SCROLL_NEVER);
        scroll.setClipToPadding(false);
        parent.addView(scroll, index, original);

        scroll.addView(grid, new ScrollView.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT));
    }

    private static void installSilhouette(Activity activity, ViewGroup root) {
        int drawableId = activity.getResources().getIdentifier(
                "vostok_inventory_silhouette_006", "drawable", activity.getPackageName());
        if (drawableId == 0) return;

        View candidate = findByIdTokens(
                root, "silhouette", "character_body", "inventory_body", "body_preview");
        if (candidate == null) return;

        if (candidate instanceof ImageView) {
            ((ImageView) candidate).setImageResource(drawableId);
        } else {
            Drawable d = activity.getDrawable(drawableId);
            candidate.setBackground(d);
        }
    }

    private static View findByIdTokens(View view, String... tokens) {
        String name = idName(view);
        for (String token : tokens) {
            if (name.contains(token)) return view;
        }
        if (view instanceof ViewGroup) {
            ViewGroup vg = (ViewGroup) view;
            for (int i = 0; i < vg.getChildCount(); i++) {
                View found = findByIdTokens(vg.getChildAt(i), tokens);
                if (found != null) return found;
            }
        }
        return null;
    }

    private static String idName(View view) {
        if (view == null || view.getId() == View.NO_ID) return "";
        try {
            return view.getResources().getResourceEntryName(view.getId()).toLowerCase();
        } catch (Throwable ignored) {
            return "";
        }
    }
}
'@
Write-Utf8NoBom $invHelperPath $invJava

$menuPath = Join-Path $javaGui "Menu.java"
if (Test-Path $menuPath) {
    Backup-File $menuPath
    $menu = Get-Content -LiteralPath $menuPath -Raw -Encoding UTF8

    if ($menu -notmatch 'VostokInventoryRuntime006\.apply') {
        $needle = 'Utils\.ShowLayout\(\s*menuLayout\s*,\s*true\s*\)\s*;'
        if ($menu -match $needle) {
            $replacement = 'Utils.ShowLayout(menuLayout, true);' + $nl +
                '        menuLayout.post(() -> VostokInventoryRuntime006.apply(NvEventQueueActivity.getInstance()));'
            $menu = [regex]::Replace($menu, $needle, $replacement, 1)
        } else {
            Write-Warning "Menu.java: menu shell anchor not found."
        }
    }

    $menu = $menu -replace '(?m)(TOTAL_SLOTS\s*=\s*)30(\s*;)', '120$2'
    $menu = $menu -replace '(?m)(EXTRA_SLOTS\s*=\s*)10(\s*;)', '10$2'
    $menu = $menu -replace '\.setColumnCount\(\s*5\s*\)', '.setColumnCount(4)'
    Write-Utf8NoBom $menuPath $menu
}

Get-ChildItem (Join-Path $res "layout") -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    if ($t -match 'Инвентар|inventory|Рюкзак|backpack') {
        $new = $t -replace 'android:columnCount="5"', 'android:columnCount="4"'
        if ($new -ne $t) {
            Backup-File $_.FullName
            Write-Utf8NoBom $_.FullName $new
        }
    }
}

$silhouettePath = Join-Path $res "drawable\vostok_inventory_silhouette_006.xml"
Backup-File $silhouettePath
$silhouette = @'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="150dp"
    android:height="300dp"
    android:viewportWidth="150"
    android:viewportHeight="300">
    <path
        android:fillColor="#00000000"
        android:strokeColor="#66FFFFFF"
        android:strokeWidth="2.3"
        android:strokeLineCap="round"
        android:strokeLineJoin="round"
        android:pathData="M75,25 C57,25 46,39 46,57 C46,75 57,88 75,88 C93,88 104,75 104,57 C104,39 93,25 75,25 Z
                          M52,94 C42,99 35,110 32,126 L20,184 C18,193 22,201 30,203 C38,205 44,200 46,191 L54,151
                          M98,94 C108,99 115,110 118,126 L130,184 C132,193 128,201 120,203 C112,205 106,200 104,191 L96,151
                          M54,103 C60,98 67,96 75,96 C83,96 90,98 96,103 L92,185 L86,199 L84,277 C84,286 80,291 74,291 C68,291 64,286 64,277 L62,202 L55,187 Z
                          M75,202 L75,286" />
</vector>
'@
Write-Utf8NoBom $silhouettePath $silhouette

Get-ChildItem (Join-Path $res "layout") -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $t = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    if ($t -match '(?i)silhouette|body_preview|character_body') {
        $new = [regex]::Replace(
            $t,
            '((?:app:srcCompat|android:src)\s*=\s*")@drawable/[^"]+(")',
            '1@drawable/vostok_inventory_silhouette_006$2',
            1)
        if ($new -ne $t) {
            Backup-File $_.FullName
            Write-Utf8NoBom $_.FullName $new
        }
    }
}

$hudCheck = Get-Content -LiteralPath $hudPath -Raw -Encoding UTF8
if ($hudCheck -match '\bImageView\s+btn_phone\b') {
    throw "VOSTOK: FIX 005A regression detected"
}

Write-Host ""
Write-Host "PASS: VOSTOK CLIENT RUNTIME FIX 006 applied." -ForegroundColor Green
Write-Host "Backup: $backup"
Write-Host "Rebuild APK in Android Studio."
