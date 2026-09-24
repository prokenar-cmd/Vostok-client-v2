param(
    [string]$ServerRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Read-Source([string]$Path) {
    $bytes = [IO.File]::ReadAllBytes($Path)

    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return @{
            Text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
            Encoding = "utf8bom"
        }
    }

    try {
        $utf8Strict = New-Object Text.UTF8Encoding($false, $true)
        $text = $utf8Strict.GetString($bytes)
        return @{ Text = $text; Encoding = "utf8" }
    }
    catch {
        $cp1251 = [Text.Encoding]::GetEncoding(1251)
        return @{ Text = $cp1251.GetString($bytes); Encoding = "cp1251" }
    }
}

function Write-Source([string]$Path, [string]$Text, [string]$EncodingName) {
    switch ($EncodingName) {
        "utf8bom" {
            $enc = New-Object Text.UTF8Encoding($true)
            [IO.File]::WriteAllText($Path, $Text, $enc)
        }
        "cp1251" {
            [IO.File]::WriteAllText($Path, $Text, [Text.Encoding]::GetEncoding(1251))
        }
        default {
            $enc = New-Object Text.UTF8Encoding($false)
            [IO.File]::WriteAllText($Path, $Text, $enc)
        }
    }
}

function Find-CurrentNewPwn {
    param([string]$ExplicitRoot)

    $candidates = @()

    if ($ExplicitRoot) {
        if (Test-Path $ExplicitRoot -PathType Leaf) {
            $candidates += Get-Item $ExplicitRoot
        } elseif (Test-Path $ExplicitRoot) {
            $candidates += Get-ChildItem $ExplicitRoot -Filter "new.pwn" -File -Recurse -ErrorAction SilentlyContinue
        }
    }

    if (!$candidates) {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $candidates += Get-ChildItem $desktop -Filter "new.pwn" -File -Recurse -ErrorAction SilentlyContinue
    }

    $scored = @()
    foreach ($file in $candidates) {
        try {
            $src = Read-Source $file.FullName
            $t = $src.Text
            $score = 0
            if ($t.Contains("DIALOG_VOSTOK_COURIER_WORK")) { $score += 10 }
            if ($t.Contains("CourierAcceptOffer")) { $score += 10 }
            if ($t.Contains("prokattest")) { $score += 5 }
            if ($t.Contains("devmodels") -or $t.Contains("DevModelViewer")) { $score += 20 }
            if ($t.Contains("VOSTOK_DEV_MODEL_VIEWER_006C")) { $score += 50 }

            if ($score -gt 0) {
                $scored += [pscustomobject]@{
                    File = $file
                    Score = $score
                    Length = $file.Length
                }
            }
        } catch {}
    }

    if (!$scored) {
        throw "VOSTOK 006D: current new.pwn was not found. Put this package next to the current server or pass -ServerRoot."
    }

    $best = $scored | Sort-Object Score, Length -Descending | Select-Object -First 1
    if ($best.Score -lt 20) {
        throw "VOSTOK 006D: found new.pwn does not look like current 006C source. Refusing unsafe patch."
    }
    return $best.File.FullName
}

function Get-PawnFunctionSpans([string]$Text) {
    $rx = [regex]'(?m)^[ \t]*(?:stock|public|forward)\s+(?:[A-Za-z_][A-Za-z0-9_]*:)?([A-Za-z_][A-Za-z0-9_]*)\s*\([^;\r\n]*\)\s*\{'
    $list = New-Object System.Collections.Generic.List[object]

    foreach ($m in $rx.Matches($Text)) {
        $open = $Text.IndexOf('{', $m.Index)
        if ($open -lt 0) { continue }

        $depth = 0
        $inString = $false
        $escaped = $false
        $lineComment = $false
        $blockComment = $false
        $close = -1

        for ($i = $open; $i -lt $Text.Length; $i++) {
            $c = $Text[$i]
            $n = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }

            if ($lineComment) {
                if ([int][char]$c -eq 10) { $lineComment = $false }
                continue
            }
            if ($blockComment) {
                if ($c -eq '*' -and $n -eq '/') { $blockComment = $false; $i++ }
                continue
            }
            if ($inString) {
                if ($escaped) { $escaped = $false; continue }
                if ($c -eq '\') { $escaped = $true; continue }
                if ($c -eq '"') { $inString = $false }
                continue
            }

            if ($c -eq '/' -and $n -eq '/') { $lineComment = $true; $i++; continue }
            if ($c -eq '/' -and $n -eq '*') { $blockComment = $true; $i++; continue }
            if ($c -eq '"') { $inString = $true; continue }

            if ($c -eq '{') { $depth++ }
            elseif ($c -eq '}') {
                $depth--
                if ($depth -eq 0) { $close = $i; break }
            }
        }

        if ($close -gt $open) {
            $list.Add([pscustomobject]@{
                Name = $m.Groups[1].Value
                Start = $m.Index
                End = $close + 1
                Header = $m.Value
            })
        }
    }

    return $list
}

function Patch-CourierMarkerSlot([string]$Text) {
    # 005E4 used slot 96; the active onboarding quest can coexist with courier.
    # Move only courier-owned marker operations to dedicated slot 95.
    $spans = Get-PawnFunctionSpans $Text
    $changes = 0

    # Apply from end to start so indices remain valid.
    foreach ($span in ($spans | Sort-Object Start -Descending)) {
        if ($span.Name -notmatch '(?i)courier') { continue }

        $body = $Text.Substring($span.Start, $span.End - $span.Start)
        $new = $body

        $new = [regex]::Replace(
            $new,
            'SetPlayerMapIcon\s*\(\s*playerid\s*,\s*96\s*,',
            'SetPlayerMapIcon(playerid, 95,'
        )
        $new = [regex]::Replace(
            $new,
            'RemovePlayerMapIcon\s*\(\s*playerid\s*,\s*96\s*\)',
            'RemovePlayerMapIcon(playerid, 95)'
        )

        if ($new -ne $body) {
            $Text = $Text.Substring(0, $span.Start) + $new + $Text.Substring($span.End)
            $changes++
        }
    }

    return @{ Text = $Text; Changes = $changes }
}

function Patch-RentalStaleGuard([string]$Text) {
    $messageIndex = $Text.IndexOf("Вы уже арендовали транспорт")
    if ($messageIndex -lt 0) {
        return @{ Text = $Text; Changed = $false; Note = "rental message not found" }
    }

    $spans = Get-PawnFunctionSpans $Text
    $fn = $null
    foreach ($s in $spans) {
        if ($messageIndex -ge $s.Start -and $messageIndex -lt $s.End) {
            $fn = $s
            break
        }
    }
    if ($null -eq $fn) {
        return @{ Text = $Text; Changed = $false; Note = "rental function not resolved" }
    }

    $body = $Text.Substring($fn.Start, $fn.End - $fn.Start)
    $localMessage = $body.IndexOf("Вы уже арендовали транспорт")
    $prefixStart = [Math]::Max(0, $localMessage - 900)
    $prefix = $body.Substring($prefixStart, $localMessage - $prefixStart)

    # Find the nearest simple vehicle-state guard:
    #   if(expr != 0)
    #   if(expr > 0)
    #   if(expr != INVALID_VEHICLE_ID)
    $guardRx = [regex]'if\s*\(\s*([A-Za-z_][A-Za-z0-9_]*(?:\s*\[[^\]\r\n]+\]){1,3})\s*(?:!=\s*(?:0|INVALID_VEHICLE_ID)|>\s*0)\s*\)'
    $matches = $guardRx.Matches($prefix)
    if ($matches.Count -eq 0) {
        return @{ Text = $Text; Changed = $false; Note = "rental guard shape unknown in " + $fn.Name }
    }

    $g = $matches[$matches.Count - 1]
    $expr = $g.Groups[1].Value.Trim()

    # Only auto-fix when the same expression is clearly used as a native vehicle id
    # somewhere in the same function.
    $escapedExpr = [regex]::Escape($expr)
    $nativeEvidence = (
        [regex]::IsMatch($body, $escapedExpr + '\s*=\s*(?:CreateVehicle|AddStaticVehicle|AddStaticVehicleEx)\s*\(') -or
        [regex]::IsMatch($body, '(?:PutPlayerInVehicle|SetVehicleParams|DestroyVehicle|IsValidVehicle)\s*\(\s*' + $escapedExpr)
    )

    if (!$nativeEvidence) {
        return @{ Text = $Text; Changed = $false; Note = "rental state is not proven native vehicle id: " + $expr }
    }

    $absoluteGuardStart = $fn.Start + $prefixStart + $g.Index
    $oldGuard = $g.Value

    # Keep the original condition and add a validity test. A stale runtime vehicle id
    # no longer blocks a new rental, while a real active rental still does.
    $conditionInside = $oldGuard.Substring($oldGuard.IndexOf('(') + 1)
    $conditionInside = $conditionInside.Substring(0, $conditionInside.LastIndexOf(')')).Trim()
    $newGuard = "if((" + $conditionInside + ") && IsValidVehicle(" + $expr + "))"

    $Text = $Text.Substring(0, $absoluteGuardStart) +
            $newGuard +
            $Text.Substring($absoluteGuardStart + $oldGuard.Length)

    return @{ Text = $Text; Changed = $true; Note = "stale native rental guard fixed in " + $fn.Name + " using " + $expr }
}

$newPwn = Find-CurrentNewPwn $ServerRoot
$src = Read-Source $newPwn
$text = $src.Text

$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "$newPwn.VOSTOK_006C_BEFORE_006D_$stamp.bak"
Copy-Item -LiteralPath $newPwn -Destination $backup -Force

$beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $newPwn).Hash.ToLower()

$marker = Patch-CourierMarkerSlot $text
$text = $marker.Text

$rental = Patch-RentalStaleGuard $text
$text = $rental.Text

if ($marker.Changes -eq 0) {
    Copy-Item -LiteralPath $backup -Destination $newPwn -Force
    throw "VOSTOK 006D: courier 005E4 marker slot was not found in current source; source restored."
}

Write-Source $newPwn $text $src.Encoding

$afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $newPwn).Hash.ToLower()
$report = @"
VOSTOK SERVER RUNTIME FIX 006D
SOURCE=$newPwn
ENCODING=$($src.Encoding)
BACKUP=$backup
SHA_BEFORE=$beforeHash
SHA_AFTER=$afterHash
COURIER_FUNCTION_BLOCKS_PATCHED=$($marker.Changes)
COURIER_MAP_ICON_SLOT=95
RENTAL_CHANGED=$($rental.Changed)
RENTAL_NOTE=$($rental.Note)

EXPECTED:
- 006C model viewer source remains present.
- courier owns map icon slot 95; donor GPS slot 98 remains untouched.
- rental stale guard is changed only if the source proves its state variable is a native vehicle id.
"@

$reportPath = Join-Path ([Environment]::GetFolderPath("Desktop")) "VOSTOK_SERVER_006D_PATCH_REPORT.txt"
[IO.File]::WriteAllText($reportPath, $report, (New-Object Text.UTF8Encoding($true)))

Write-Host ""
Write-Host "PASS: VOSTOK SERVER RUNTIME FIX 006D source prepared." -ForegroundColor Green
Write-Host "new.pwn: $newPwn"
Write-Host "report:  $reportPath"
if (!$rental.Changed) {
    Write-Host "NOTE: rental fix was not auto-applied because the source guard was not provably safe." -ForegroundColor Yellow
    Write-Host "The report was generated; do not remove the rental guard blindly."
}
