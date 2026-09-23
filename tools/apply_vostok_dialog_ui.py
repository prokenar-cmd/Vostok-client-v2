#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

MARKER = "VOSTOK_DIALOG_UI_001"


def find_one(root: Path, name: str, required: tuple[str, ...]) -> Path:
    matches = []
    for p in root.rglob(name):
        try:
            s = p.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        if all(token in s for token in required):
            matches.append(p)
    if len(matches) != 1:
        raise RuntimeError(f"{name}: expected exactly 1 match, got {len(matches)}: {matches}")
    return matches[0]


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")
    print(f"[WRITE] {path}")


def patch_manager(path: Path) -> None:
    s = path.read_text(encoding="utf-8")
    if MARKER in s:
        print(f"[SKIP] {path} already patched")
        return

    pat = re.compile(
        r"(?ms)^\s*public void loadSizes\(\)\s*\{.*?^\s*public void loadButtons\(\)\s*\{"
    )
    replacement = r'''
    // VOSTOK_DIALOG_UI_001: fixed-width modal layout.
    // Do not let long/short server strings resize the dialog or produce the old
    // crooked "Пусто" list geometry. The RecyclerView always occupies the card.
    public void loadSizes() {
        ConstraintLayout.LayoutParams listLayoutParams =
                (ConstraintLayout.LayoutParams) this.mDialogListLayout.getLayoutParams();
        listLayoutParams.width = 0;
        this.mDialogListLayout.setLayoutParams(listLayoutParams);

        ConstraintLayout.LayoutParams listParams =
                (ConstraintLayout.LayoutParams) this.mDialogList.getLayoutParams();
        listParams.width = 0;
        this.mDialogList.setLayoutParams(listParams);

        ConstraintLayout.LayoutParams recyclerParams =
                (ConstraintLayout.LayoutParams) this.mDialogListRecycler.getLayoutParams();
        recyclerParams.width = 0;
        this.mDialogListRecycler.setLayoutParams(recyclerParams);

        if (this.mListAdapter != null) {
            this.mListAdapter.setMatchParent(true);
        }

        this.mDialogBody.post(new Runnable() {
            public void run() {
                if (DialogManager.this.mDialogStyle == 5 && DialogManager.this.mListAdapter != null) {
                    DialogManager dialogManager = DialogManager.this;
                    dialogManager.mTabSizes =
                            dialogManager.mListAdapter.mergeTabSizes(DialogManager.this.mTabSizes);

                    for (int i = 0; i < 4; i++) {
                        ViewGroup.LayoutParams lp = DialogManager.this.mDialogTabField[i].getLayoutParams();
                        lp.width = DialogManager.this.mTabSizes[i];
                        DialogManager.this.mDialogTabField[i].setLayoutParams(lp);
                    }
                }
            }
        });
    }

    public void loadButtons() {'''
    s2, n = pat.subn(replacement, s, count=1)
    if n != 1:
        raise RuntimeError(f"Could not patch loadSizes() in {path}")

    # Leave one durable marker near the class declaration.
    s2 = s2.replace(
        "public class DialogManager {",
        "public class DialogManager {\n    // " + MARKER,
        1,
    )
    path.write_text(s2, encoding="utf-8", newline="\n")
    print(f"[PATCH] {path}")


def patch_adapter(path: Path) -> None:
    s = path.read_text(encoding="utf-8")
    if MARKER in s:
        print(f"[SKIP] {path} already patched")
        return

    # New dialog card is always full width. Keeping this default also prevents
    # a one-frame wrap_content jump before DialogManager.loadSizes() runs.
    s2, n = re.subn(
        r"boolean\s+mNeedMatchParent\s*=\s*false\s*;",
        "boolean mNeedMatchParent = true; // " + MARKER,
        s,
        count=1,
    )
    if n != 1:
        # Some forks omit the explicit initializer.
        s2 = s.replace(
            "boolean mNeedMatchParent;",
            "boolean mNeedMatchParent = true; // " + MARKER,
            1,
        )
        if s2 == s:
            raise RuntimeError(f"Could not patch mNeedMatchParent in {path}")

    path.write_text(s2, encoding="utf-8", newline="\n")
    print(f"[PATCH] {path}")


def dialog_xml(custom_recycler_tag: str) -> str:
    return f'''<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#66000000">

    <!-- {MARKER}: one modal language for every SA-MP dialog. -->
    <androidx.constraintlayout.widget.ConstraintLayout
        android:id="@+id/dialog"
        android:layout_width="760.0px"
        android:layout_height="wrap_content"
        android:background="@drawable/vostok_dialog_panel"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent">

        <androidx.constraintlayout.widget.ConstraintLayout
            android:id="@+id/dialog_body"
            android:layout_width="680.0px"
            android:layout_height="wrap_content"
            android:layout_marginStart="40.0px"
            android:layout_marginTop="24.0px"
            android:layout_marginEnd="40.0px"
            android:layout_marginBottom="28.0px"
            app:layout_constraintBottom_toBottomOf="parent"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintHeight_max="650.0px"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toTopOf="parent">

            <View
                android:id="@+id/vostok_dialog_grabber"
                android:layout_width="58.0px"
                android:layout_height="5.0px"
                android:background="@drawable/vostok_dialog_grabber"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toTopOf="parent" />

            <TextView
                android:id="@+id/dialog_caption"
                android:layout_width="0.0dip"
                android:layout_height="wrap_content"
                android:layout_marginTop="24.0px"
                android:ellipsize="end"
                android:fontFamily="sans-serif-black"
                android:lines="1"
                android:maxLines="1"
                android:singleLine="true"
                android:text="Заголовок"
                android:textColor="#FFFFFFFF"
                android:textSize="30.0px"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/vostok_dialog_grabber" />

            <ScrollView
                android:id="@+id/dialog_text_layout"
                android:layout_width="0.0dip"
                android:layout_height="wrap_content"
                android:layout_marginTop="18.0px"
                android:layout_marginBottom="20.0px"
                android:fillViewport="true"
                android:scrollbars="none"
                android:visibility="gone"
                app:layout_constraintBottom_toTopOf="@+id/dialog_buttons"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintHeight_max="360.0px"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/dialog_caption"
                app:layout_constraintVertical_bias="0.0">

                <LinearLayout
                    android:layout_width="match_parent"
                    android:layout_height="wrap_content"
                    android:background="@drawable/vostok_dialog_content"
                    android:orientation="vertical"
                    android:paddingStart="22.0px"
                    android:paddingTop="18.0px"
                    android:paddingEnd="22.0px"
                    android:paddingBottom="18.0px">

                    <TextView
                        android:id="@+id/dialog_text"
                        android:layout_width="match_parent"
                        android:layout_height="wrap_content"
                        android:fontFamily="sans-serif"
                        android:lineSpacingExtra="5.0px"
                        android:text="Текст"
                        android:textColor="#F2FFFFFF"
                        android:textSize="24.0px" />
                </LinearLayout>
            </ScrollView>

            <androidx.constraintlayout.widget.ConstraintLayout
                android:id="@+id/dialog_input_layout"
                android:layout_width="0.0dip"
                android:layout_height="wrap_content"
                android:layout_marginTop="14.0px"
                android:layout_marginBottom="20.0px"
                android:background="@drawable/vostok_dialog_input"
                android:visibility="gone"
                app:layout_constraintBottom_toTopOf="@+id/dialog_buttons"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/dialog_text_layout">

                <EditText
                    android:id="@+id/dialog_input"
                    android:layout_width="0.0dip"
                    android:layout_height="wrap_content"
                    android:background="@android:color/transparent"
                    android:fontFamily="sans-serif-medium"
                    android:hint="Нажмите для ввода"
                    android:imeOptions="flagNoExtractUi"
                    android:inputType="textShortMessage"
                    android:lines="1"
                    android:maxLines="1"
                    android:paddingStart="22.0px"
                    android:paddingTop="17.0px"
                    android:paddingEnd="22.0px"
                    android:paddingBottom="17.0px"
                    android:singleLine="true"
                    android:textColor="#FFFFFFFF"
                    android:textColorHint="#80FFFFFF"
                    android:textSize="24.0px"
                    app:layout_constraintBottom_toBottomOf="parent"
                    app:layout_constraintEnd_toEndOf="parent"
                    app:layout_constraintStart_toStartOf="parent"
                    app:layout_constraintTop_toTopOf="parent" />
            </androidx.constraintlayout.widget.ConstraintLayout>

            <androidx.constraintlayout.widget.ConstraintLayout
                android:id="@+id/dialog_list_layout"
                android:layout_width="0.0dip"
                android:layout_height="380.0px"
                android:layout_marginTop="18.0px"
                android:layout_marginBottom="20.0px"
                android:background="@drawable/vostok_dialog_content"
                android:visibility="gone"
                app:layout_constraintBottom_toTopOf="@+id/dialog_buttons"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/dialog_caption">

                <androidx.constraintlayout.widget.ConstraintLayout
                    android:id="@+id/dialog_tablist_row"
                    android:layout_width="0.0dip"
                    android:layout_height="wrap_content"
                    android:paddingStart="20.0px"
                    android:paddingTop="12.0px"
                    android:paddingEnd="20.0px"
                    android:paddingBottom="10.0px"
                    android:visibility="gone"
                    app:layout_constraintEnd_toEndOf="parent"
                    app:layout_constraintStart_toStartOf="parent"
                    app:layout_constraintTop_toTopOf="parent">

                    <TextView
                        android:id="@+id/dialog_field1"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="sans-serif-bold"
                        android:lines="1"
                        android:maxLines="1"
                        android:paddingEnd="16.0px"
                        android:singleLine="true"
                        android:text="Field1"
                        android:textColor="#FFFFFFFF"
                        android:textSize="22.0px"
                        app:layout_constraintStart_toStartOf="parent"
                        app:layout_constraintTop_toTopOf="parent" />

                    <TextView
                        android:id="@+id/dialog_field2"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="sans-serif-bold"
                        android:lines="1"
                        android:maxLines="1"
                        android:paddingEnd="16.0px"
                        android:singleLine="true"
                        android:text="Field2"
                        android:textColor="#FFFFFFFF"
                        android:textSize="22.0px"
                        app:layout_constraintStart_toEndOf="@+id/dialog_field1"
                        app:layout_constraintTop_toTopOf="parent" />

                    <TextView
                        android:id="@+id/dialog_field3"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="sans-serif-bold"
                        android:lines="1"
                        android:maxLines="1"
                        android:paddingEnd="16.0px"
                        android:singleLine="true"
                        android:text="Field3"
                        android:textColor="#FFFFFFFF"
                        android:textSize="22.0px"
                        app:layout_constraintStart_toEndOf="@+id/dialog_field2"
                        app:layout_constraintTop_toTopOf="parent" />

                    <TextView
                        android:id="@+id/dialog_field4"
                        android:layout_width="wrap_content"
                        android:layout_height="wrap_content"
                        android:fontFamily="sans-serif-bold"
                        android:lines="1"
                        android:maxLines="1"
                        android:paddingEnd="16.0px"
                        android:singleLine="true"
                        android:text="Field4"
                        android:textColor="#FFFFFFFF"
                        android:textSize="22.0px"
                        app:layout_constraintStart_toEndOf="@+id/dialog_field3"
                        app:layout_constraintTop_toTopOf="parent" />
                </androidx.constraintlayout.widget.ConstraintLayout>

                <androidx.constraintlayout.widget.ConstraintLayout
                    android:id="@+id/dialog_list"
                    android:layout_width="0.0dip"
                    android:layout_height="0.0dip"
                    app:layout_constraintBottom_toBottomOf="parent"
                    app:layout_constraintEnd_toEndOf="parent"
                    app:layout_constraintStart_toStartOf="parent"
                    app:layout_constraintTop_toBottomOf="@+id/dialog_tablist_row">

                    <{custom_recycler_tag}
                        android:id="@+id/dialog_list_recycler"
                        android:layout_width="0.0dip"
                        android:layout_height="0.0dip"
                        android:layout_marginStart="8.0px"
                        android:layout_marginTop="8.0px"
                        android:layout_marginEnd="8.0px"
                        android:layout_marginBottom="8.0px"
                        android:fadeScrollbars="false"
                        android:overScrollMode="never"
                        android:scrollbarAlwaysDrawVerticalTrack="false"
                        android:scrollbarSize="8.0px"
                        android:scrollbarThumbVertical="@drawable/vostok_dialog_scroll_thumb"
                        android:scrollbarTrackVertical="@drawable/vostok_dialog_scroll_track"
                        android:scrollbars="vertical"
                        android:verticalScrollbarPosition="right"
                        app:layout_constraintBottom_toBottomOf="parent"
                        app:layout_constraintEnd_toEndOf="parent"
                        app:layout_constraintStart_toStartOf="parent"
                        app:layout_constraintTop_toTopOf="parent" />
                </androidx.constraintlayout.widget.ConstraintLayout>
            </androidx.constraintlayout.widget.ConstraintLayout>

            <androidx.constraintlayout.widget.ConstraintLayout
                android:id="@+id/dialog_buttons"
                android:layout_width="wrap_content"
                android:layout_height="70.0px"
                android:layout_marginTop="18.0px"
                app:layout_constraintBottom_toBottomOf="parent"
                app:layout_constraintEnd_toEndOf="parent"
                app:layout_constraintStart_toStartOf="parent"
                app:layout_constraintTop_toBottomOf="@+id/dialog_caption"
                app:layout_constraintVertical_bias="1.0">

                <androidx.constraintlayout.widget.ConstraintLayout
                    android:id="@+id/button_positive"
                    android:layout_width="290.0px"
                    android:layout_height="70.0px"
                    android:background="@drawable/vostok_dialog_button_primary"
                    app:layout_constraintBottom_toBottomOf="parent"
                    app:layout_constraintStart_toStartOf="parent"
                    app:layout_constraintTop_toTopOf="parent">

                    <TextView
                        android:id="@+id/button_positive_text"
                        android:layout_width="0.0dip"
                        android:layout_height="0.0dip"
                        android:fontFamily="sans-serif-bold"
                        android:gravity="center"
                        android:lines="1"
                        android:maxLines="1"
                        android:singleLine="true"
                        android:text="Выбрать"
                        android:textColor="#FFFFFFFF"
                        android:textSize="23.0px"
                        app:layout_constraintBottom_toBottomOf="parent"
                        app:layout_constraintEnd_toEndOf="parent"
                        app:layout_constraintStart_toStartOf="parent"
                        app:layout_constraintTop_toTopOf="parent" />
                </androidx.constraintlayout.widget.ConstraintLayout>

                <androidx.constraintlayout.widget.ConstraintLayout
                    android:id="@+id/button_negative"
                    android:layout_width="290.0px"
                    android:layout_height="70.0px"
                    android:layout_marginStart="14.0px"
                    android:background="@drawable/vostok_dialog_button_secondary"
                    android:visibility="visible"
                    app:layout_constraintBottom_toBottomOf="parent"
                    app:layout_constraintEnd_toEndOf="parent"
                    app:layout_constraintStart_toEndOf="@+id/button_positive"
                    app:layout_constraintTop_toTopOf="parent">

                    <TextView
                        android:id="@+id/button_negative_text"
                        android:layout_width="0.0dip"
                        android:layout_height="0.0dip"
                        android:fontFamily="sans-serif-bold"
                        android:gravity="center"
                        android:lines="1"
                        android:maxLines="1"
                        android:singleLine="true"
                        android:text="Назад"
                        android:textColor="#FFFFFFFF"
                        android:textSize="23.0px"
                        app:layout_constraintBottom_toBottomOf="parent"
                        app:layout_constraintEnd_toEndOf="parent"
                        app:layout_constraintStart_toStartOf="parent"
                        app:layout_constraintTop_toTopOf="parent" />
                </androidx.constraintlayout.widget.ConstraintLayout>
            </androidx.constraintlayout.widget.ConstraintLayout>
        </androidx.constraintlayout.widget.ConstraintLayout>
    </androidx.constraintlayout.widget.ConstraintLayout>
</androidx.constraintlayout.widget.ConstraintLayout>
'''


DIALOG_ITEM = '''<?xml version="1.0" encoding="utf-8"?>
<androidx.constraintlayout.widget.ConstraintLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    android:layout_width="match_parent"
    android:layout_height="64.0px"
    android:background="@drawable/vostok_dialog_row"
    android:paddingStart="10.0px"
    android:paddingEnd="16.0px">

    <ImageView
        android:id="@+id/item_bg"
        android:layout_width="0.0dip"
        android:layout_height="0.0dip"
        android:scaleType="fitXY"
        android:visibility="gone"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintEnd_toEndOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent"
        app:srcCompat="@drawable/vostok_dialog_row_selected" />

    <TextView
        android:id="@+id/item_field1"
        android:layout_width="wrap_content"
        android:layout_height="0.0dip"
        android:fontFamily="sans-serif-medium"
        android:gravity="center_vertical"
        android:lines="1"
        android:maxLines="1"
        android:paddingStart="12.0px"
        android:paddingEnd="16.0px"
        android:singleLine="true"
        android:text="Field1"
        android:textColor="#FFFFFFFF"
        android:textSize="22.0px"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toStartOf="parent"
        app:layout_constraintTop_toTopOf="parent" />

    <TextView
        android:id="@+id/item_field2"
        android:layout_width="wrap_content"
        android:layout_height="0.0dip"
        android:fontFamily="sans-serif-medium"
        android:gravity="center_vertical"
        android:lines="1"
        android:maxLines="1"
        android:paddingEnd="16.0px"
        android:singleLine="true"
        android:text="Field2"
        android:textColor="#FFFFFFFF"
        android:textSize="22.0px"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toEndOf="@+id/item_field1"
        app:layout_constraintTop_toTopOf="parent" />

    <TextView
        android:id="@+id/item_field3"
        android:layout_width="wrap_content"
        android:layout_height="0.0dip"
        android:fontFamily="sans-serif-medium"
        android:gravity="center_vertical"
        android:lines="1"
        android:maxLines="1"
        android:paddingEnd="16.0px"
        android:singleLine="true"
        android:text="Field3"
        android:textColor="#FFFFFFFF"
        android:textSize="22.0px"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toEndOf="@+id/item_field2"
        app:layout_constraintTop_toTopOf="parent" />

    <TextView
        android:id="@+id/item_field4"
        android:layout_width="wrap_content"
        android:layout_height="0.0dip"
        android:fontFamily="sans-serif-medium"
        android:gravity="center_vertical"
        android:lines="1"
        android:maxLines="1"
        android:paddingEnd="16.0px"
        android:singleLine="true"
        android:text="Field4"
        android:textColor="#FFFFFFFF"
        android:textSize="22.0px"
        app:layout_constraintBottom_toBottomOf="parent"
        app:layout_constraintStart_toEndOf="@+id/item_field3"
        app:layout_constraintTop_toTopOf="parent" />
</androidx.constraintlayout.widget.ConstraintLayout>
'''


DRAWABLES = {
    "vostok_dialog_panel.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#F2262832"/>
    <stroke android:width="1.0px" android:color="#26FFFFFF"/>
    <corners android:radius="30.0px"/>
</shape>
''',
    "vostok_dialog_content.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FF30323C"/>
    <stroke android:width="1.0px" android:color="#1FFFFFFF"/>
    <corners android:radius="16.0px"/>
</shape>
''',
    "vostok_dialog_input.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#FF30323C"/>
    <stroke android:width="1.0px" android:color="#33FFFFFF"/>
    <corners android:radius="15.0px"/>
</shape>
''',
    "vostok_dialog_grabber.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#5CFFFFFF"/>
    <corners android:radius="100.0px"/>
</shape>
''',
    "vostok_dialog_button_primary.xml": '''<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_pressed="true">
        <shape android:shape="rectangle">
            <solid android:color="#FF7A3A"/>
            <corners android:radius="18.0px"/>
        </shape>
    </item>
    <item>
        <shape android:shape="rectangle">
            <solid android:color="#F2642D"/>
            <corners android:radius="18.0px"/>
        </shape>
    </item>
</selector>
''',
    "vostok_dialog_button_secondary.xml": '''<?xml version="1.0" encoding="utf-8"?>
<selector xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:state_pressed="true">
        <shape android:shape="rectangle">
            <solid android:color="#444650"/>
            <corners android:radius="18.0px"/>
        </shape>
    </item>
    <item>
        <shape android:shape="rectangle">
            <solid android:color="#353740"/>
            <stroke android:width="1.0px" android:color="#22FFFFFF"/>
            <corners android:radius="18.0px"/>
        </shape>
    </item>
</selector>
''',
    "vostok_dialog_row.xml": '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:bottom="1.0px">
        <shape android:shape="rectangle">
            <solid android:color="#0030323C"/>
        </shape>
    </item>
    <item android:top="63.0px">
        <shape android:shape="rectangle">
            <solid android:color="#18FFFFFF"/>
        </shape>
    </item>
</layer-list>
''',
    "vostok_dialog_row_selected.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#52F2642D"/>
    <stroke android:width="2.0px" android:color="#E6F2642D"/>
    <corners android:radius="13.0px"/>
</shape>
''',
    "vostok_dialog_scroll_thumb.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#F2642D"/>
    <corners android:radius="100.0px"/>
</shape>
''',
    "vostok_dialog_scroll_track.xml": '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#26FFFFFF"/>
    <corners android:radius="100.0px"/>
</shape>
''',
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("root", nargs="?", default=".", help="Android client source root")
    args = ap.parse_args()
    root = Path(args.root).resolve()

    dialog = find_one(
        root,
        "dialog.xml",
        ("@+id/dialog_caption", "@+id/dialog_list_recycler", "@+id/button_positive"),
    )
    item = find_one(
        root,
        "dialog_item.xml",
        ("@+id/item_bg", "@+id/item_field1"),
    )
    manager = find_one(
        root,
        "DialogManager.java",
        ("class DialogManager", "mDialogListRecycler", "public void loadSizes()"),
    )
    adapter = find_one(
        root,
        "DialogAdapter.java",
        ("class DialogAdapter", "mNeedMatchParent", "item_field1"),
    )

    old_dialog = dialog.read_text(encoding="utf-8", errors="ignore")
    m = re.search(r"<([A-Za-z0-9_.$]+CustomRecyclerView)\b", old_dialog)
    if not m:
        raise RuntimeError("Could not detect the existing CustomRecyclerView class from dialog.xml")
    custom_tag = m.group(1)
    print(f"[INFO] CustomRecyclerView = {custom_tag}")

    res = dialog.parents[1]
    drawable = res / "drawable"

    write(dialog, dialog_xml(custom_tag))
    write(item, DIALOG_ITEM)
    for name, body in DRAWABLES.items():
        write(drawable / name, body)

    patch_manager(manager)
    patch_adapter(adapter)

    # Post-checks: no donor blue gradient in our new dialog surface.
    final = dialog.read_text(encoding="utf-8")
    required = [
        "@drawable/vostok_dialog_panel",
        "@drawable/vostok_dialog_button_primary",
        "@drawable/vostok_dialog_scroll_thumb",
        "@+id/dialog_caption",
        "@+id/dialog_list_recycler",
    ]
    for token in required:
        if token not in final:
            raise RuntimeError(f"post-check failed: missing {token}")

    if "#008BF6" in final or "#1900FD" in final:
        raise RuntimeError("post-check failed: donor blue survived in dialog.xml")

    print("PASS: VOSTOK Dialog UI 001 applied")
    print(f"dialog={dialog}")
    print(f"item={item}")
    print(f"manager={manager}")
    print(f"adapter={adapter}")


if __name__ == "__main__":
    main()
