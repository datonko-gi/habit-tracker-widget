Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class Native {
    [DllImport("user32.dll")]
    public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    [DllImport("dwmapi.dll")]
    public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    [DllImport("user32.dll")]
    public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")]
    public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public const uint MOD_ALT = 0x1;
    public const uint MOD_CONTROL = 0x2;
    public const uint MOD_SHIFT = 0x4;
    public static readonly IntPtr HWND_BOTTOM = new IntPtr(1);
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const uint SWP_NOMOVE = 0x0002;
    public const uint SWP_NOSIZE = 0x0001;
    public const uint SWP_NOACTIVATE = 0x0010;
    public const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    public const int DWMWCP_ROUND = 2;
}
"@

# HotkeyHook — subclasses the form's WndProc to catch WM_HOTKEY and raise a managed event.
Add-Type -TypeDefinition @"
using System;
using System.Windows.Forms;

public class HotkeyHook : NativeWindow {
    public event Action HotkeyPressed;
    public void Hook(IntPtr h) { AssignHandle(h); }
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x0312) {
            if (HotkeyPressed != null) HotkeyPressed();
        }
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms"

# ===== Geometry =====
$script:CELL       = 9
$script:GAP        = 2
$script:WEEKS      = 20
$script:TPAD       = 5
$script:RPAD       = 6
$script:BPAD       = 5
$script:SUM_GAP    = 5
$script:LABEL_GAP  = 3
$script:LABEL_H    = 9
$script:INIT_TOP    = 10
$script:INIT_RIGHT  = 169

# Round knob on the left
$script:BTN_X      = 8
$script:BTN_D      = 54
$script:BTN_GAP    = 8
$script:LPAD       = $script:BTN_X + $script:BTN_D + $script:BTN_GAP

# Cluster (knob + goal name + square switcher), vertically centered in the left column
$script:NAME_H     = 13
$script:SW_SQ      = 7
$script:SW_GAP     = 3
$script:CL_G1      = 16  # gap knob -> name (kept wide so clicking the goal never hits the knob)
$script:CL_G2      = 5   # gap name -> switcher
$script:CL_BIAS    = 4   # shift whole cluster up by this much (knob sits higher)

$script:FormW = $script:LPAD + $script:WEEKS * ($script:CELL + $script:GAP) - $script:GAP + $script:RPAD
$script:FormH = $script:TPAD + 7 * ($script:CELL + $script:GAP) - $script:GAP + $script:SUM_GAP + $script:CELL + $script:LABEL_GAP + $script:LABEL_H + $script:BPAD

# ===== Per-goal palettes (soft, muted, one hue per goal slot; cycles for extra goals) =====
function NewPal($dR,$dG,$dB,$eR,$eG,$eB,$bR,$bG,$bB,$mR,$mG,$mB,$fR,$fG,$fB,$ktR,$ktG,$ktB,$kbR,$kbG,$kbB,$sR,$sG,$sB) {
    return @{
        done   = [System.Drawing.Color]::FromArgb($dR,$dG,$dB)
        empty  = [System.Drawing.Color]::FromArgb($eR,$eG,$eB)
        bg     = [System.Drawing.Color]::FromArgb($bR,$bG,$bB)
        met    = [System.Drawing.Color]::FromArgb($mR,$mG,$mB)
        future = [System.Drawing.Color]::FromArgb($fR,$fG,$fB)
        knobT  = [System.Drawing.Color]::FromArgb($ktR,$ktG,$ktB)
        knobB  = [System.Drawing.Color]::FromArgb($kbR,$kbG,$kbB)
        sw     = [System.Drawing.Color]::FromArgb($sR,$sG,$sB)
    }
}
$script:Palettes = @(
    (NewPal 95 95 95   215 215 215  235 235 235  110 188 110  228 228 228  210 210 215  105 105 112  110 110 116),   # 0 English  neutral grey
    (NewPal 92 112 134 209 214 221  232 234 238  120 172 205  224 227 233  199 206 217  96 112 132   100 140 180),   # 1 Push ups  slate blue
    (NewPal 140 112 84 223 217 210  238 235 231  212 168 96   233 228 222  217 206 193  134 108 84   188 148 90),    # 2 Calories  warm amber
    (NewPal 92 124 96  212 219 212  233 237 233  130 185 135  226 231 226  202 212 202  96 126 100   120 165 120),   # 3 sage green
    (NewPal 120 98 124 219 213 221  237 233 238  175 135 180  231 226 232  213 205 215  120 100 124  160 120 165)    # 4 soft plum
)
$script:ColorBorder = [System.Drawing.Color]::FromArgb(40,40,40)
$script:ColorLabel  = [System.Drawing.Color]::FromArgb(120,120,120)
$script:ColorName   = [System.Drawing.Color]::FromArgb(64,64,70)
$script:ColorSwIdle = [System.Drawing.Color]::FromArgb(205,205,208)

function Get-Palette($idx) {
    return $script:Palettes[$idx % $script:Palettes.Count]
}

# ===== Data (v2 = multiple goals) =====
$script:DataDir  = Join-Path $env:APPDATA "HabitWidget"
$script:DataFile = Join-Path $script:DataDir "data.json"
if (-not (Test-Path $script:DataDir)) { New-Item -ItemType Directory -Path $script:DataDir -Force | Out-Null }

function New-DefaultGoals {
    return @(
        @{ name = "English";  days = @{}; threshold = 4 },
        @{ name = "Push ups"; days = @{}; threshold = 4 },
        @{ name = "Calories"; days = @{}; threshold = 4 }
    )
}

function ConvertTo-DaysHash($daysObj) {
    $days = @{}
    if ($daysObj) {
        foreach ($p in $daysObj.PSObject.Properties) { $days[$p.Name] = [bool]$p.Value }
    }
    return $days
}

function Clamp-Threshold($t) {
    $n = 4
    if ([int]::TryParse([string]$t, [ref]$n) -and $n -ge 1 -and $n -le 7) { return $n }
    return 4
}

function Load-Data {
    if (-not (Test-Path $script:DataFile)) {
        return @{ goals = (New-DefaultGoals); active = 0; posX = $null; posY = $null }
    }
    try {
        $raw = Get-Content $script:DataFile -Raw -ErrorAction Stop
        $obj = $raw | ConvertFrom-Json -ErrorAction Stop
        $px = $null; $py = $null
        if ($obj.PSObject.Properties.Name -contains 'posX') { $px = $obj.posX }
        if ($obj.PSObject.Properties.Name -contains 'posY') { $py = $obj.posY }

        $ver = 1
        if ($obj.PSObject.Properties.Name -contains 'version') { $ver = [int]$obj.version }

        if ($ver -ge 2 -and ($obj.PSObject.Properties.Name -contains 'goals')) {
            $goals = @()
            foreach ($g in @($obj.goals)) {
                $nm = "Goal"
                if ($g.PSObject.Properties.Name -contains 'name' -and $g.name) { $nm = [string]$g.name }
                $goals += @{ name = $nm; days = (ConvertTo-DaysHash $g.days); threshold = (Clamp-Threshold $g.threshold) }
            }
            if ($goals.Count -eq 0) { $goals = New-DefaultGoals }
            $active = 0
            if ($obj.PSObject.Properties.Name -contains 'active') { $active = [int]$obj.active }
            if ($active -lt 0) { $active = 0 }
            if ($active -ge $goals.Count) { $active = $goals.Count - 1 }
            return @{ goals = $goals; active = $active; posX = $px; posY = $py }
        }

        # ---- migrate v1 (single goal) ----
        $name = "English"
        if ($obj.PSObject.Properties.Name -contains 'goal' -and $obj.goal) { $name = [string]$obj.goal }
        $first = @{ name = $name; days = (ConvertTo-DaysHash $obj.days); threshold = (Clamp-Threshold $obj.threshold) }
        $goals = @($first, @{ name = "Push ups"; days = @{}; threshold = 4 }, @{ name = "Calories"; days = @{}; threshold = 4 })
        return @{ goals = $goals; active = 0; posX = $px; posY = $py }
    } catch {
        return @{ goals = (New-DefaultGoals); active = 0; posX = $null; posY = $null }
    }
}

function Save-Data {
    $goalsOut = @()
    foreach ($g in $script:Data.goals) {
        $goalsOut += [PSCustomObject]@{ name = $g.name; days = $g.days; threshold = $g.threshold }
    }
    $obj = [PSCustomObject]@{
        version = 2
        goals   = @($goalsOut)
        active  = $script:Data.active
        posX    = $script:Data.posX
        posY    = $script:Data.posY
    }
    try {
        $obj | ConvertTo-Json -Depth 6 -Compress | Set-Content -Path $script:DataFile -Encoding UTF8
    } catch {}
}

$script:Data = Load-Data

function Active-Goal { return $script:Data.goals[$script:Data.active] }

# ===== Cluster layout (knob + name + switcher squares) =====
function Get-Cluster {
    $btnD = $script:BTN_D
    $clusterH = $btnD + $script:CL_G1 + $script:NAME_H + $script:CL_G2 + $script:SW_SQ
    $top   = [int](($script:FormH - $clusterH) / 2) - $script:CL_BIAS
    if ($top -lt 3) { $top = 3 }
    $knobY = $top
    $nameY = $top + $btnD + $script:CL_G1
    $swY   = $nameY + $script:NAME_H + $script:CL_G2
    $cx    = $script:BTN_X + $btnD / 2.0
    $n     = $script:Data.goals.Count
    $tot   = $n * $script:SW_SQ + ($n - 1) * $script:SW_GAP
    $startX = $cx - $tot / 2.0
    $rects = @()
    for ($i = 0; $i -lt $n; $i++) {
        $rx = $startX + $i * ($script:SW_SQ + $script:SW_GAP)
        $rects += ,([PSCustomObject]@{ i = $i; x = $rx; y = $swY; w = $script:SW_SQ; h = $script:SW_SQ })
    }
    return [PSCustomObject]@{ knobY = $knobY; nameY = $nameY; swY = $swY; cx = $cx; rects = $rects }
}
$script:Cluster = Get-Cluster

# ===== Time helpers (Pacific) =====
try {
    $script:PTZ = [System.TimeZoneInfo]::FindSystemTimeZoneById("Pacific Standard Time")
} catch {
    $script:PTZ = [System.TimeZoneInfo]::Local
}
function Get-PTNow { [System.TimeZoneInfo]::ConvertTime([DateTime]::UtcNow, $script:PTZ) }
function Get-MondayOf($d) {
    $dow = [int]$d.DayOfWeek
    $off = if ($dow -eq 0) { 6 } else { $dow - 1 }
    return $d.Date.AddDays(-$off)
}
function Format-DKey($d) { $d.ToString("yyyy-MM-dd") }

# ===== Form =====
$form = New-Object System.Windows.Forms.Form
$form.Size = New-Object System.Drawing.Size($script:FormW, $script:FormH)
$form.FormBorderStyle = "None"
$form.ShowInTaskbar = $false
$form.StartPosition = "Manual"
$form.BackColor = (Get-Palette $script:Data.active).bg
$form.TopMost = $false
$form.Text = "HabitWidget"

$scr = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -ne $script:Data.posX -and $null -ne $script:Data.posY) {
    $form.Location = New-Object System.Drawing.Point([int]$script:Data.posX, [int]$script:Data.posY)
} else {
    $defX = $scr.Right - $script:FormW - $script:INIT_RIGHT
    $defY = $scr.Top + $script:INIT_TOP
    $form.Location = New-Object System.Drawing.Point([int]$defX, [int]$defY)
}

$panel = New-Object System.Windows.Forms.Panel
$panel.Dock = "Fill"
$panel.BackColor = (Get-Palette $script:Data.active).bg
$form.Controls.Add($panel)

$panelType = $panel.GetType()
$prop = $panelType.GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::NonPublic -bor [System.Reflection.BindingFlags]::Instance)
$prop.SetValue($panel, $true, $null)

# ===== Drawing =====
$panel.Add_Paint({
    param($s, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    $pal      = Get-Palette $script:Data.active
    $goal     = Active-Goal
    $days     = $goal.days
    $thr      = [int]$goal.threshold

    $now           = Get-PTNow
    $today         = $now.Date
    $todayKey      = Format-DKey $today
    $currentMonday = Get-MondayOf $now
    $leftMonday    = $currentMonday.AddDays(-($script:WEEKS - 1) * 7)

    $weekCounts = @{}
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        $cnt = 0
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            if ($d -gt $today) { continue }
            $k = Format-DKey $d
            if ($days.ContainsKey($k) -and $days[$k]) { $cnt++ }
        }
        $weekCounts[$c] = $cnt
    }

    $emptyBrush  = New-Object System.Drawing.SolidBrush($pal.empty)
    $doneBrush   = New-Object System.Drawing.SolidBrush($pal.done)
    $metBrush    = New-Object System.Drawing.SolidBrush($pal.met)
    $futureBrush = New-Object System.Drawing.SolidBrush($pal.future)
    $borderPen   = New-Object System.Drawing.Pen($script:ColorBorder, 1)

    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            $x = $script:LPAD + $c * ($script:CELL + $script:GAP)
            $y = $script:TPAD + $r * ($script:CELL + $script:GAP)
            if ($d -gt $today) {
                $g.FillRectangle($futureBrush, $x, $y, $script:CELL, $script:CELL)
                continue
            }
            $k = Format-DKey $d
            $brush = $emptyBrush
            if ($days.ContainsKey($k) -and $days[$k]) { $brush = $doneBrush }
            $g.FillRectangle($brush, $x, $y, $script:CELL, $script:CELL)
            if ($k -eq $todayKey) {
                $g.DrawRectangle($borderPen, $x - 1, $y - 1, $script:CELL + 1, $script:CELL + 1)
            }
        }
    }

    # Summary row
    $summaryY = $script:TPAD + 7 * ($script:CELL + $script:GAP) - $script:GAP + $script:SUM_GAP
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        if ($wkMon -gt $today) { continue }
        $x = $script:LPAD + $c * ($script:CELL + $script:GAP)
        $brush = $emptyBrush
        if ($weekCounts[$c] -ge $thr) { $brush = $metBrush }
        $g.FillRectangle($brush, $x, $summaryY, $script:CELL, $script:CELL)
    }

    # Month labels
    $labelY = $summaryY + $script:CELL + $script:LABEL_GAP
    $font = New-Object System.Drawing.Font("Segoe UI", 7)
    $labelBrush = New-Object System.Drawing.SolidBrush($script:ColorLabel)
    for ($c = 0; $c -lt $script:WEEKS; $c++) {
        $wkMon = $leftMonday.AddDays($c * 7)
        for ($r = 0; $r -lt 7; $r++) {
            $d = $wkMon.AddDays($r)
            if ($d.Day -eq 1) {
                $txt = $d.ToString("MMM", [System.Globalization.CultureInfo]::InvariantCulture)
                $x = $script:LPAD + $c * ($script:CELL + $script:GAP) - 2
                $g.DrawString($txt, $font, $labelBrush, [float]$x, [float]$labelY)
                break
            }
        }
    }

    $cl = $script:Cluster

    # ----- Knob (tinted by active goal) -----
    for ($i = 3; $i -ge 1; $i--) {
        $a = 25 - ($i * 5)
        $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb($a, 0, 0, 0))
        $g.FillEllipse($sh, ($script:BTN_X + $i - 1), ($cl.knobY + $i), $script:BTN_D, $script:BTN_D)
        $sh.Dispose()
    }
    $bodyRect = New-Object System.Drawing.RectangleF([float]$script:BTN_X, [float]$cl.knobY, [float]$script:BTN_D, [float]$script:BTN_D)
    $grad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($bodyRect, $pal.knobT, $pal.knobB, 90.0)
    $g.FillEllipse($grad, $script:BTN_X, $cl.knobY, $script:BTN_D, $script:BTN_D)
    $grad.Dispose()
    $rimPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(80, 0, 0, 0), 1.0)
    $g.DrawEllipse($rimPen, $script:BTN_X, $cl.knobY, $script:BTN_D, $script:BTN_D)
    $rimPen.Dispose()
    $hlW = $script:BTN_D * 0.62
    $hlH = $script:BTN_D * 0.28
    $hlX = $script:BTN_X + ($script:BTN_D - $hlW) / 2.0
    $hlY = $cl.knobY + $script:BTN_D * 0.09
    $hlRect = New-Object System.Drawing.RectangleF([float]$hlX, [float]$hlY, [float]$hlW, [float]$hlH)
    $hlGrad = New-Object System.Drawing.Drawing2D.LinearGradientBrush($hlRect,
        [System.Drawing.Color]::FromArgb(160, 255, 255, 255),
        [System.Drawing.Color]::FromArgb(0, 255, 255, 255), 90.0)
    $g.FillEllipse($hlGrad, [float]$hlX, [float]$hlY, [float]$hlW, [float]$hlH)
    $hlGrad.Dispose()

    # ----- Goal name (centered under the knob) -----
    $nameFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular)
    $nameBrush = New-Object System.Drawing.SolidBrush($script:ColorName)
    $nameFmt = New-Object System.Drawing.StringFormat
    $nameFmt.Alignment = [System.Drawing.StringAlignment]::Center
    $nameFmt.LineAlignment = [System.Drawing.StringAlignment]::Center
    $nameRect = New-Object System.Drawing.RectangleF([float]2, [float]$cl.nameY, [float]($script:LPAD - 4), [float]$script:NAME_H)
    $g.DrawString([string]$goal.name, $nameFont, $nameBrush, $nameRect, $nameFmt)
    $nameFont.Dispose(); $nameBrush.Dispose()

    # ----- Square switcher (one square per goal; active = goal hue + outline) -----
    $idleBrush = New-Object System.Drawing.SolidBrush($script:ColorSwIdle)
    foreach ($r in $cl.rects) {
        if ($r.i -eq $script:Data.active) {
            $sb = New-Object System.Drawing.SolidBrush($pal.sw)
            $g.FillRectangle($sb, [float]$r.x, [float]$r.y, [float]$r.w, [float]$r.h)
            $sb.Dispose()
            $op = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 0, 0, 0), 1.0)
            $g.DrawRectangle($op, [float]($r.x - 1), [float]($r.y - 1), [float]($r.w + 1), [float]($r.h + 1))
            $op.Dispose()
        } else {
            $g.FillRectangle($idleBrush, [float]$r.x, [float]$r.y, [float]$r.w, [float]$r.h)
        }
    }
    $idleBrush.Dispose()

    $emptyBrush.Dispose(); $doneBrush.Dispose(); $metBrush.Dispose(); $futureBrush.Dispose()
    $borderPen.Dispose(); $font.Dispose(); $labelBrush.Dispose()
})

# ===== Click vs drag =====
$script:Drag = @{ Down=$false; Dragging=$false; StartSX=0; StartSY=0; FormStartX=0; FormStartY=0; ClickX=0; ClickY=0 }

function Is-InButton($x, $y) {
    $cx = $script:BTN_X + $script:BTN_D / 2.0
    $cy = $script:Cluster.knobY + $script:BTN_D / 2.0
    $dx = $x - $cx
    $dy = $y - $cy
    $r  = $script:BTN_D / 2.0
    return (($dx * $dx + $dy * $dy) -le ($r * $r))
}

function Hit-Switcher($x, $y) {
    foreach ($r in $script:Cluster.rects) {
        if ($x -ge ($r.x - 3) -and $x -le ($r.x + $r.w + 3) -and $y -ge ($r.y - 4) -and $y -le ($r.y + $r.h + 4)) {
            return [int]$r.i
        }
    }
    return -1
}

function Is-InName($x, $y) {
    $ny = $script:Cluster.nameY
    return ($y -ge ($ny - 2) -and $y -le ($ny + $script:NAME_H + 2) -and $x -ge 2 -and $x -le ($script:LPAD - 4))
}

function Set-ActiveGoal($i) {
    if ($i -lt 0 -or $i -ge $script:Data.goals.Count) { return }
    if ($i -eq $script:Data.active) { return }
    $script:Data.active = $i
    $pal = Get-Palette $i
    $form.BackColor = $pal.bg
    $panel.BackColor = $pal.bg
    Save-Data
    $panel.Invalidate()
}

function Try-MarkToday {
    $now = Get-PTNow
    $k = Format-DKey $now.Date
    $goal = Active-Goal
    if (-not $goal.days.ContainsKey($k) -or -not $goal.days[$k]) {
        $goal.days[$k] = $true
        Save-Data
        $panel.Invalidate()
    }
}

function Unmark-Today {
    $now = Get-PTNow
    $k = Format-DKey $now.Date
    $goal = Active-Goal
    if ($goal.days.ContainsKey($k)) {
        $goal.days.Remove($k)
        Save-Data
        $panel.Invalidate()
    }
}

$panel.Add_MouseDown({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    $script:Drag.Down = $true
    $script:Drag.Dragging = $false
    $pt = [System.Windows.Forms.Cursor]::Position
    $script:Drag.StartSX = $pt.X
    $script:Drag.StartSY = $pt.Y
    $script:Drag.FormStartX = $form.Location.X
    $script:Drag.FormStartY = $form.Location.Y
    $script:Drag.ClickX = $e.X
    $script:Drag.ClickY = $e.Y
})

$panel.Add_MouseMove({
    param($s, $e)
    if (-not $script:Drag.Down) { return }
    $pt = [System.Windows.Forms.Cursor]::Position
    $dx = $pt.X - $script:Drag.StartSX
    $dy = $pt.Y - $script:Drag.StartSY
    if (-not $script:Drag.Dragging) {
        if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 4) { $script:Drag.Dragging = $true }
    }
    if ($script:Drag.Dragging) {
        $nx = $script:Drag.FormStartX + $dx
        $ny = $script:Drag.FormStartY + $dy
        $form.Location = New-Object System.Drawing.Point([int]$nx, [int]$ny)
    }
})

$panel.Add_MouseUp({
    param($s, $e)
    if ($e.Button -ne [System.Windows.Forms.MouseButtons]::Left) { return }
    if ($script:Drag.Down) {
        if ($script:Drag.Dragging) {
            $script:Data.posX = $form.Location.X
            $script:Data.posY = $form.Location.Y
            Save-Data
        } else {
            $cx = $script:Drag.ClickX; $cy = $script:Drag.ClickY
            if (Is-InButton $cx $cy) {
                Try-MarkToday
            } else {
                $hit = Hit-Switcher $cx $cy
                if ($hit -ge 0) {
                    Set-ActiveGoal $hit
                } elseif (Is-InName $cx $cy) {
                    Set-ActiveGoal ((($script:Data.active) + 1) % $script:Data.goals.Count)
                }
            }
        }
    }
    $script:Drag.Down = $false
    $script:Drag.Dragging = $false
})

# ===== Timer (day/week rollover) =====
$script:LastTodayKey = Format-DKey ((Get-PTNow).Date)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({
    $nk = Format-DKey ((Get-PTNow).Date)
    if ($nk -ne $script:LastTodayKey) {
        $script:LastTodayKey = $nk
        $panel.Invalidate()
    }
})
$timer.Start()

# ===== Right-click context menu (configure goals) =====
[void][System.Reflection.Assembly]::LoadWithPartialName('Microsoft.VisualBasic')

function Rename-Goal {
    $goal = Active-Goal
    $current = [string]$goal.name
    $new = [Microsoft.VisualBasic.Interaction]::InputBox("Rename goal:", "Rename goal", $current)
    if ($null -ne $new -and $new.Trim() -ne "" -and $new -ne $current) {
        $goal.name = $new.Trim()
        Save-Data
        $panel.Invalidate()
    }
}

function Add-Goal {
    $new = [Microsoft.VisualBasic.Interaction]::InputBox("New goal name:", "Add goal", "")
    if ($null -ne $new -and $new.Trim() -ne "") {
        $script:Data.goals += @{ name = $new.Trim(); days = @{}; threshold = 4 }
        $script:Cluster = Get-Cluster
        Save-Data
        Set-ActiveGoal ($script:Data.goals.Count - 1)
        $panel.Invalidate()
    }
}

function Remove-Goal {
    if ($script:Data.goals.Count -le 1) {
        [System.Windows.Forms.MessageBox]::Show("Cannot remove the last goal.", "HabitWidget",
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }
    $goal = Active-Goal
    $res = [System.Windows.Forms.MessageBox]::Show(
        "Remove goal '$($goal.name)' and all its marked days?", "Remove goal",
        [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $idx = $script:Data.active
    $new = @()
    for ($i = 0; $i -lt $script:Data.goals.Count; $i++) { if ($i -ne $idx) { $new += $script:Data.goals[$i] } }
    $script:Data.goals = $new
    if ($script:Data.active -ge $script:Data.goals.Count) { $script:Data.active = $script:Data.goals.Count - 1 }
    $script:Cluster = Get-Cluster
    $pal = Get-Palette $script:Data.active
    $form.BackColor = $pal.bg; $panel.BackColor = $pal.bg
    Save-Data
    $panel.Invalidate()
}

function Edit-Threshold {
    $goal = Active-Goal
    $current = [string]$goal.threshold
    $input = [Microsoft.VisualBasic.Interaction]::InputBox("Days per week to turn the summary green (1-7):", "Weekly goal", $current)
    if ($null -eq $input) { return }
    $n = 0
    if ([int]::TryParse($input.Trim(), [ref]$n) -and $n -ge 1 -and $n -le 7) {
        $goal.threshold = $n
        Save-Data
        $panel.Invalidate()
    }
}

$ctx = New-Object System.Windows.Forms.ContextMenuStrip
$script:MenuHeader = $ctx.Items.Add("")
$script:MenuHeader.Enabled = $false
[void]$ctx.Items.Add("-")
$script:MenuThresholdItem = $ctx.Items.Add("", $null, { Edit-Threshold })
[void]$ctx.Items.Add("Rename goal...", $null, { Rename-Goal })
[void]$ctx.Items.Add("Add goal...", $null, { Add-Goal })
$script:MenuRemoveItem = $ctx.Items.Add("Remove this goal", $null, { Remove-Goal })
[void]$ctx.Items.Add("Unmark today", $null, { Unmark-Today })
[void]$ctx.Items.Add("-")
[void]$ctx.Items.Add("Close widget", $null, { $form.Close() })
$ctx.add_Opening({
    $goal = Active-Goal
    $script:MenuHeader.Text = "$($goal.name)  ($($script:Data.active + 1)/$($script:Data.goals.Count))"
    $script:MenuThresholdItem.Text = "Weekly goal: $([int]$goal.threshold) days..."
})
$form.ContextMenuStrip = $ctx
$panel.ContextMenuStrip = $ctx

# ===== Pin below other windows =====
function Sink-ToBottom {
    [Native]::SetWindowPos($form.Handle, [Native]::HWND_BOTTOM, 0, 0, 0, 0,
        [Native]::SWP_NOMOVE -bor [Native]::SWP_NOSIZE -bor [Native]::SWP_NOACTIVATE) | Out-Null
}

$script:HotkeyId = 1
$script:Hook = $null

$form.Add_Shown({
    try {
        $h = $form.Handle
        $ex = [Native]::GetWindowLong($h, [Native]::GWL_EXSTYLE)
        [Native]::SetWindowLong($h, [Native]::GWL_EXSTYLE,
            $ex -bor [Native]::WS_EX_NOACTIVATE -bor [Native]::WS_EX_TOOLWINDOW) | Out-Null
        $pref = [Native]::DWMWCP_ROUND
        [Native]::DwmSetWindowAttribute($h, [Native]::DWMWA_WINDOW_CORNER_PREFERENCE, [ref]$pref, 4) | Out-Null
        Sink-ToBottom

        $script:Hook = New-Object HotkeyHook
        $script:Hook.Hook($h)
        $script:Hook.add_HotkeyPressed({ Try-MarkToday })
        $mods = [Native]::MOD_CONTROL -bor [Native]::MOD_ALT -bor [Native]::MOD_SHIFT
        $vkO = 0x4F
        [Native]::RegisterHotKey($h, $script:HotkeyId, $mods, $vkO) | Out-Null
    } catch {}
    $panel.Invalidate()
})

$sinkTimer = New-Object System.Windows.Forms.Timer
$sinkTimer.Interval = 3000
$sinkTimer.Add_Tick({ Sink-ToBottom })
$sinkTimer.Start()

$form.Add_FormClosed({
    try { [Native]::UnregisterHotKey($form.Handle, $script:HotkeyId) | Out-Null } catch {}
    Save-Data
})

[System.Windows.Forms.Application]::EnableVisualStyles()
$form.ShowDialog() | Out-Null
