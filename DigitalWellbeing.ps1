<#
.SYNOPSIS
    Digital Wellbeing - A high-quality GUI application for monitoring and managing screen time.

.DESCRIPTION
    This PowerShell script creates a modern WPF-based Digital Wellbeing application with:
    - Real-time app usage tracking
    - Screen time monitoring with daily/weekly stats
    - Per-application time limits with notifications
    - Parental controls (PIN-protected) with app blocking and bedtime schedules
    - Beautiful Material Design-inspired dashboard

.NOTES
    Author: Sumit (HackWithSumit)
    Requires: Windows PowerShell 5.1+ or PowerShell 7+ with Windows
    Run as Administrator for full functionality (process monitoring, app blocking)
#>

#Requires -Version 5.1

param(
    [switch]$ResetData,
    [switch]$RunAsAdmin,
    [switch]$Background
)

# ── Hide Console/PowerShell Window (from screen and taskbar) ──
try {
    Add-Type -Name ConsoleWindow -Namespace Win32Helper -MemberDefinition @"
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")]
    public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")]
    public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TOOLWINDOW = 0x00000080;
    public const int WS_EX_APPWINDOW = 0x00040000;
"@ -ErrorAction SilentlyContinue
} catch { }
try {
    $consoleHwnd = [Win32Helper.ConsoleWindow]::GetConsoleWindow()
    if ($consoleHwnd -ne [IntPtr]::Zero) {
        $exStyle = [Win32Helper.ConsoleWindow]::GetWindowLong($consoleHwnd, [Win32Helper.ConsoleWindow]::GWL_EXSTYLE)
        $exStyle = $exStyle -band (-bnot [Win32Helper.ConsoleWindow]::WS_EX_APPWINDOW)
        $exStyle = $exStyle -bor [Win32Helper.ConsoleWindow]::WS_EX_TOOLWINDOW
        [Win32Helper.ConsoleWindow]::SetWindowLong($consoleHwnd, [Win32Helper.ConsoleWindow]::GWL_EXSTYLE, $exStyle) | Out-Null
        [Win32Helper.ConsoleWindow]::ShowWindow($consoleHwnd, 0) | Out-Null
    }
} catch { }

# ── Elevate to Administrator if needed ──
if ($RunAsAdmin -and -not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -RunAsAdmin" -Verb RunAs
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ══════════════════════════════════════════════════════════════════════
# WINDOWS STARTUP & SYSTEM TRAY
# ══════════════════════════════════════════════════════════════════════

$script:StartupRegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$script:StartupRegName = "DigitalWellbeing"
$script:TrayIcon = $null

function Get-StartupCommand {
    # Detect if running as a compiled exe (PS2EXE, etc.)
    $exePath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $isExe = $exePath -and ($exePath -match '\.exe$') -and ($exePath -notmatch 'powershell|pwsh')

    if ($isExe) {
        return "`"$exePath`" -Background"
    }

    $scriptPath = if ($PSCommandPath) { $PSCommandPath } elseif ($MyInvocation.ScriptName) { $MyInvocation.ScriptName } else { $script:MyInvocation.MyCommand.Path }
    if (-not $scriptPath) {
        $scriptPath = Join-Path $PSScriptRoot "DigitalWellbeing.ps1"
    }
    return "powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`" -Background"
}

function Set-WindowsStartup {
    param([bool]$Enable)
    try {
        if ($Enable) {
            $cmd = Get-StartupCommand
            if (-not (Test-Path $script:StartupRegPath)) {
                New-Item -Path $script:StartupRegPath -Force | Out-Null
            }
            New-ItemProperty -Path $script:StartupRegPath -Name $script:StartupRegName -Value $cmd -PropertyType String -Force -ErrorAction SilentlyContinue | Out-Null
            Set-ItemProperty -Path $script:StartupRegPath -Name $script:StartupRegName -Value $cmd -Force
        } else {
            Remove-ItemProperty -Path $script:StartupRegPath -Name $script:StartupRegName -ErrorAction SilentlyContinue
        }
    } catch { }
}

function Test-WindowsStartup {
    try {
        $val = Get-ItemProperty -Path $script:StartupRegPath -Name $script:StartupRegName -ErrorAction Stop
        return ($null -ne $val.$($script:StartupRegName))
    } catch { return $false }
}

function New-TrayIcon {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.Clear([System.Drawing.Color]::Transparent)

    # Gradient circle background (purple)
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)),
        (New-Object System.Drawing.Point(32, 32)),
        [System.Drawing.Color]::FromArgb(108, 99, 255),
        [System.Drawing.Color]::FromArgb(90, 82, 213)
    )
    $g.FillEllipse($bgBrush, 1, 1, 30, 30)

    # Clock circle (white outline)
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
    $g.DrawEllipse($pen, 7, 7, 18, 18)

    # Clock hands (white)
    $centerX = 16; $centerY = 16
    # Hour hand (pointing to ~10 o'clock)
    $g.DrawLine($pen, $centerX, $centerY, 12, 11)
    # Minute hand (pointing to ~12 o'clock)
    $g.DrawLine($pen, $centerX, $centerY, 16, 9)

    # Center dot
    $g.FillEllipse([System.Drawing.Brushes]::White, 14, 14, 4, 4)

    # Small accent dot (bottom-right, pink/accent)
    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 101, 132))
    $g.FillEllipse($accentBrush, 23, 23, 7, 7)

    $pen.Dispose()
    $bgBrush.Dispose()
    $accentBrush.Dispose()
    $g.Dispose()

    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    return $icon
}

function Initialize-TrayIcon {
    $script:TrayIcon = New-Object System.Windows.Forms.NotifyIcon
    $script:TrayIcon.Text = "Digital Wellbeing"
    $script:TrayIcon.Icon = New-TrayIcon
    $script:TrayIcon.Visible = $true

    # Context menu
    $trayMenu = New-Object System.Windows.Forms.ContextMenuStrip

    $showItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $showItem.Text = "Show Digital Wellbeing"
    $showItem.Font = New-Object System.Drawing.Font($showItem.Font, [System.Drawing.FontStyle]::Bold)
    $showItem.Add_Click({
        $window.Show()
        $window.ShowInTaskbar = $true
        $window.WindowState = 'Normal'
        $window.Activate()
    })
    $trayMenu.Items.Add($showItem) | Out-Null

    $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    $statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $statusItem.Text = "Tracking: Active"
    $statusItem.Enabled = $false
    $trayMenu.Items.Add($statusItem) | Out-Null
    $script:TrayStatusItem = $statusItem

    $trayMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

    $exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $exitItem.Text = "Exit"
    $exitItem.Add_Click({
        # If PIN is set, require PIN to exit
        if ($script:ParentalConfig.PinHash) {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $enteredPin = [Microsoft.VisualBasic.Interaction]::InputBox(
                "Enter PIN to exit Digital Wellbeing:",
                "PIN Required to Exit",
                ""
            )
            if (-not $enteredPin) { return }
            $hash = Get-HashString $enteredPin
            if ($hash -ne $script:ParentalConfig.PinHash) {
                [System.Windows.Forms.MessageBox]::Show(
                    "Incorrect PIN. Exit denied.",
                    "Wrong PIN",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }
        }
        $script:ForceClose = $true
        $script:TrayIcon.Visible = $false
        $script:TrayIcon.Dispose()
        Save-JsonData -Path $DataFile -Data $script:UsageData
        Save-JsonData -Path $ConfigFile -Data $script:Config
        $window.Close()
    })
    $trayMenu.Items.Add($exitItem) | Out-Null

    $script:TrayIcon.ContextMenuStrip = $trayMenu

    # Single-click tray icon to show window
    $script:TrayIcon.Add_Click({
        $window.Show()
        $window.ShowInTaskbar = $true
        $window.WindowState = 'Normal'
        $window.Activate()
    })
}

$script:ForceClose = $false
$script:BlockedByLimit = @{}
$script:LimitNotifyCooldown = @{}

# ── Win32 API for Foreground Window Detection & Global Hotkey ──
try {
    Add-Type @"
        using System;
        using System.Runtime.InteropServices;
        using System.Text;
        public class ForegroundWindow {
            [DllImport("user32.dll")]
            public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")]
            public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
            [DllImport("user32.dll", CharSet = CharSet.Unicode)]
            public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
        }
        public class KeyboardHelper {
            [DllImport("user32.dll")]
            public static extern short GetAsyncKeyState(int vKey);
            public const int VK_CONTROL = 0x11;
            public const int VK_SHIFT = 0x10;
            public const int VK_D = 0x44;

            public static bool IsCtrlShiftDPressed() {
                return (GetAsyncKeyState(VK_CONTROL) & 0x8000) != 0
                    && (GetAsyncKeyState(VK_SHIFT) & 0x8000) != 0
                    && (GetAsyncKeyState(VK_D) & 0x8000) != 0;
            }
        }
"@ -ErrorAction SilentlyContinue
} catch { }

# ══════════════════════════════════════════════════════════════════════
# DATA LAYER - Persistence & Configuration
# ══════════════════════════════════════════════════════════════════════

$script:AppDataPath = Join-Path $env:APPDATA "DigitalWellbeing"
$script:DataFile = Join-Path $AppDataPath "usage_data.json"
$script:ConfigFile = Join-Path $AppDataPath "config.json"
$script:LimitsFile = Join-Path $AppDataPath "limits.json"
$script:ParentalFile = Join-Path $AppDataPath "parental.json"

if (-not (Test-Path $AppDataPath)) {
    New-Item -ItemType Directory -Path $AppDataPath -Force | Out-Null
}

if ($ResetData) {
    Remove-Item "$AppDataPath\*.json" -Force -ErrorAction SilentlyContinue
}

function Get-DefaultConfig {
    return @{
        Theme              = "Dark"
        TrackingEnabled    = $true
        NotificationsEnabled = $true
        StartWithWindows   = $false
        UpdateIntervalSec  = 5
        MinimizeToTray     = $true
    }
}

function Get-DefaultParentalConfig {
    return @{
        Enabled         = $false
        PinHash         = ""
        BlockedApps     = @()
        BedtimeEnabled  = $false
        BedtimeStart    = "22:00"
        BedtimeEnd      = "07:00"
        DailyLimitMin   = 0
        WeeklyReports   = $true
    }
}

function Save-JsonData {
    param([string]$Path, [object]$Data)
    $Data | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8
}

function Load-JsonData {
    param([string]$Path, [object]$Default)
    if (Test-Path $Path) {
        try {
            $content = Get-Content -Path $Path -Raw -Encoding UTF8
            if ($content) { return $content | ConvertFrom-Json }
        } catch { }
    }
    if ($null -ne $Default) {
        Save-JsonData -Path $Path -Data $Default
        return $Default
    }
    return $null
}

function Get-HashString {
    param([string]$Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = $sha.ComputeHash($bytes)
    return [BitConverter]::ToString($hash) -replace '-', ''
}

# Load configuration
$script:Config = Load-JsonData -Path $ConfigFile -Default (Get-DefaultConfig)
$script:Limits = Load-JsonData -Path $LimitsFile -Default ([PSCustomObject]@{})
$script:ParentalConfig = Load-JsonData -Path $ParentalFile -Default (Get-DefaultParentalConfig)

# Initialize today's usage data
$script:TodayKey = (Get-Date).ToString("yyyy-MM-dd")
$script:UsageData = Load-JsonData -Path $DataFile -Default ([PSCustomObject]@{})

if (-not $script:UsageData.PSObject.Properties[$script:TodayKey]) {
    $script:UsageData | Add-Member -NotePropertyName $TodayKey -NotePropertyValue ([PSCustomObject]@{}) -Force
    Save-JsonData -Path $DataFile -Data $script:UsageData
}

# ══════════════════════════════════════════════════════════════════════
# TRACKING ENGINE
# ══════════════════════════════════════════════════════════════════════

$script:TrackingTimer = $null
$script:LastActiveApp = ""
$script:LastCheckTime = Get-Date
$script:SessionStart = Get-Date
$script:TotalScreenTimeToday = 0
$script:CurrentAppUsage = @{}
$script:CurrentTheme = $null

function Get-RunningApps {
    $apps = @()
    try {
        $processes = Get-Process | Where-Object {
            $_.MainWindowTitle -ne "" -and
            $_.ProcessName -notin @("svchost", "csrss", "wininit", "winlogon", "dwm", "conhost",
                                      "RuntimeBroker", "SearchHost", "StartMenuExperienceHost",
                                      "ShellExperienceHost", "TextInputHost", "SecurityHealthSystray",
                                      "SystemSettings", "LockApp", "LogiOverlay")
        } | Select-Object ProcessName, MainWindowTitle, Id, @{N='CPU';E={$_.CPU}},
                          @{N='MemoryMB';E={[math]::Round($_.WorkingSet64 / 1MB, 1)}},
                          @{N='StartTime';E={$_.StartTime}} -Unique

        foreach ($proc in $processes) {
            $friendlyName = Get-FriendlyAppName -ProcessName $proc.ProcessName -ProcessId $proc.Id
            $apps += @{
                Name       = $friendlyName
                ProcessName = $proc.ProcessName
                Title      = $proc.MainWindowTitle
                PID        = $proc.Id
                CPU        = [math]::Round($proc.CPU, 1)
                MemoryMB   = $proc.MemoryMB
                StartTime  = if ($proc.StartTime) { $proc.StartTime.ToString("HH:mm:ss") } else { "N/A" }
            }
        }
    } catch { }
    return $apps
}

function Get-ForegroundApp {
    try {
        $hwnd = [ForegroundWindow]::GetForegroundWindow()
        $procId = [uint32]0
        [ForegroundWindow]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        $sb = New-Object System.Text.StringBuilder 256
        [ForegroundWindow]::GetWindowText($hwnd, $sb, 256) | Out-Null
        $friendlyName = Get-FriendlyAppName -ProcessName $proc.ProcessName -ProcessId $procId
        return @{
            Name  = $friendlyName
            ProcessName = $proc.ProcessName
            Title = $sb.ToString()
            PID   = $procId
        }
    } catch {
        return @{ Name = "Unknown"; ProcessName = "Unknown"; Title = ""; PID = 0 }
    }
}

function Update-UsageTracking {
    $now = Get-Date
    $elapsed = ($now - $script:LastCheckTime).TotalSeconds
    $script:LastCheckTime = $now
    $script:TotalScreenTimeToday += $elapsed

    # Enforce blocked apps every cycle
    Enforce-BlockedApps

    $fg = Get-ForegroundApp
    $appName = $fg.Name
    $procName = $fg.ProcessName

    if ($appName -and $appName -ne "Unknown" -and $appName -ne "Idle") {
        if (-not $script:CurrentAppUsage.ContainsKey($appName)) {
            $script:CurrentAppUsage[$appName] = 0
        }
        $script:CurrentAppUsage[$appName] += $elapsed

        # Update persistent data
        $todayData = $script:UsageData.$script:TodayKey
        if ($todayData -is [PSCustomObject]) {
            if (-not $todayData.PSObject.Properties[$appName]) {
                $todayData | Add-Member -NotePropertyName $appName -NotePropertyValue 0 -Force
            }
            $todayData.$appName += $elapsed
        }

        # Check time limits (auto-close + block reopen)
        Check-TimeLimits -AppName $appName -ProcessName $procName

        # Check parental controls
        Check-ParentalControls -AppName $appName
    }

    # Save data periodically (every 30 seconds)
    if ([int]$script:TotalScreenTimeToday % 30 -lt $script:Config.UpdateIntervalSec) {
        Save-JsonData -Path $DataFile -Data $script:UsageData
    }
}

function Check-TimeLimits {
    param([string]$AppName, [string]$ProcessName)
    if ($script:Limits.PSObject -and $script:Limits.PSObject.Properties[$AppName]) {
        $limitMin = $script:Limits.$AppName
        $usedSec = $script:CurrentAppUsage[$AppName]
        $usedMin = [math]::Floor($usedSec / 60)

        if ($limitMin -gt 0 -and $usedMin -ge $limitMin) {
            # Add to blocked list so reopening is blocked
            if (-not $script:BlockedByLimit.ContainsKey($ProcessName)) {
                $script:BlockedByLimit[$ProcessName] = $AppName
            }
            # Kill the app
            try {
                Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            } catch { }
            # Notify (with 60s cooldown per app)
            $now = Get-Date
            $lastNotify = $script:LimitNotifyCooldown[$AppName]
            if (-not $lastNotify -or ($now - $lastNotify).TotalSeconds -ge 60) {
                $script:LimitNotifyCooldown[$AppName] = $now
                if ($script:Config.NotificationsEnabled) {
                    Show-Notification -Title "Time Limit Reached" -Message "$AppName has been closed. Daily limit of $limitMin minutes reached." -Type "Warning"
                }
            }
        } elseif ($limitMin -gt 0 -and $usedMin -ge ($limitMin - 5) -and $usedMin -lt $limitMin) {
            $now = Get-Date
            $warnKey = "${AppName}_warn"
            $lastWarn = $script:LimitNotifyCooldown[$warnKey]
            if (-not $lastWarn -or ($now - $lastWarn).TotalSeconds -ge 60) {
                $script:LimitNotifyCooldown[$warnKey] = $now
                if ($script:Config.NotificationsEnabled) {
                    Show-Notification -Title "Time Limit Warning" -Message "$AppName has $($limitMin - $usedMin) minutes remaining." -Type "Info"
                }
            }
        }
    }
}

function Enforce-BlockedApps {
    if ($script:BlockedByLimit.Count -eq 0) { return }
    foreach ($procName in @($script:BlockedByLimit.Keys)) {
        $appName = $script:BlockedByLimit[$procName]
        # Verify the limit is still exceeded (in case data was reset)
        $stillBlocked = $false
        if ($script:Limits.PSObject -and $script:Limits.PSObject.Properties[$appName]) {
            $limitMin = $script:Limits.$appName
            $usedSec = if ($script:CurrentAppUsage.ContainsKey($appName)) { $script:CurrentAppUsage[$appName] } else { 0 }
            $usedMin = [math]::Floor($usedSec / 60)
            if ($limitMin -gt 0 -and $usedMin -ge $limitMin) {
                $stillBlocked = $true
            }
        }
        if ($stillBlocked) {
            try {
                $running = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($running) {
                    $running | Stop-Process -Force -ErrorAction SilentlyContinue
                    $now = Get-Date
                    $lastNotify = $script:LimitNotifyCooldown[$appName]
                    if (-not $lastNotify -or ($now - $lastNotify).TotalSeconds -ge 60) {
                        $script:LimitNotifyCooldown[$appName] = $now
                        Show-Notification -Title "App Blocked" -Message "$appName is blocked. Daily time limit reached." -Type "Warning"
                    }
                }
            } catch { }
        } else {
            $script:BlockedByLimit.Remove($procName)
        }
    }
}

function Check-ParentalControls {
    param([string]$AppName)
    if ($script:ParentalConfig.Enabled) {
        # Check blocked apps
        if ($script:ParentalConfig.BlockedApps -contains $AppName) {
            try {
                Stop-Process -Name $AppName -Force -ErrorAction SilentlyContinue
                Show-Notification -Title "App Blocked" -Message "$AppName is blocked by Parental Controls." -Type "Warning"
            } catch { }
        }

        # Check bedtime
        if ($script:ParentalConfig.BedtimeEnabled) {
            $now = Get-Date
            $bedStart = [DateTime]::ParseExact($script:ParentalConfig.BedtimeStart, "HH:mm", $null)
            $bedEnd = [DateTime]::ParseExact($script:ParentalConfig.BedtimeEnd, "HH:mm", $null)
            $currentTime = $now.TimeOfDay

            $isBedtime = $false
            if ($bedStart.TimeOfDay -gt $bedEnd.TimeOfDay) {
                $isBedtime = $currentTime -ge $bedStart.TimeOfDay -or $currentTime -lt $bedEnd.TimeOfDay
            } else {
                $isBedtime = $currentTime -ge $bedStart.TimeOfDay -and $currentTime -lt $bedEnd.TimeOfDay
            }

            if ($isBedtime) {
                Show-Notification -Title "Bedtime Mode" -Message "It's bedtime! Please put your device away." -Type "Warning"
            }
        }
    }
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [string]$Type = "Info"
    )
    try {
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon.Visible = $true
        $tipIcon = switch ($Type) {
            "Warning" { [System.Windows.Forms.ToolTipIcon]::Warning }
            "Error"   { [System.Windows.Forms.ToolTipIcon]::Error }
            default   { [System.Windows.Forms.ToolTipIcon]::Info }
        }
        $notifyIcon.ShowBalloonTip(5000, $Title, $Message, $tipIcon)
        Start-Sleep -Milliseconds 100
    } catch { }
}

function Format-Duration {
    param([double]$Seconds)
    if ($Seconds -lt 60) { return "$([math]::Round($Seconds))s" }
    $minutes = [math]::Floor($Seconds / 60)
    $secs = [math]::Floor($Seconds % 60)
    if ($minutes -lt 60) { return "${minutes}m ${secs}s" }
    $hours = [math]::Floor($minutes / 60)
    $mins = $minutes % 60
    return "${hours}h ${mins}m"
}

# ── Friendly App Name Resolution ──
$script:AppNameCache = @{}
$script:KnownAppNames = @{
    "chrome"            = "Google Chrome"
    "msedge"            = "Microsoft Edge"
    "firefox"           = "Mozilla Firefox"
    "brave"             = "Brave Browser"
    "opera"             = "Opera Browser"
    "iexplore"          = "Internet Explorer"
    "Code"              = "Visual Studio Code"
    "devenv"            = "Visual Studio"
    "WINWORD"           = "Microsoft Word"
    "EXCEL"             = "Microsoft Excel"
    "POWERPNT"          = "Microsoft PowerPoint"
    "ONENOTE"           = "Microsoft OneNote"
    "OUTLOOK"           = "Microsoft Outlook"
    "Teams"             = "Microsoft Teams"
    "ms-teams"          = "Microsoft Teams"
    "Spotify"           = "Spotify"
    "Discord"           = "Discord"
    "slack"             = "Slack"
    "Telegram"          = "Telegram"
    "WhatsApp"          = "WhatsApp"
    "explorer"          = "File Explorer"
    "notepad"           = "Notepad"
    "notepad++"         = "Notepad++"
    "WindowsTerminal"   = "Windows Terminal"
    "powershell"        = "PowerShell"
    "pwsh"              = "PowerShell"
    "cmd"               = "Command Prompt"
    "mspaint"           = "Paint"
    "SnippingTool"      = "Snipping Tool"
    "ScreenSketch"      = "Snip & Sketch"
    "Calculator"        = "Calculator"
    "Photos"            = "Photos"
    "Video.UI"          = "Movies & TV"
    "WinStore.App"      = "Microsoft Store"
    "Taskmgr"           = "Task Manager"
    "mmc"               = "Management Console"
    "regedit"           = "Registry Editor"
    "control"           = "Control Panel"
    "SystemSettings"    = "Settings"
    "ApplicationFrameHost" = "UWP App Host"
    "SearchApp"         = "Windows Search"
    "Widgets"           = "Widgets"
    "PhoneExperienceHost" = "Phone Link"
    "GameBar"           = "Xbox Game Bar"
    "XboxApp"           = "Xbox"
    "Steam"             = "Steam"
    "EpicGamesLauncher" = "Epic Games Launcher"
    "vlc"               = "VLC Media Player"
    "wmplayer"          = "Windows Media Player"
    "Acrobat"           = "Adobe Acrobat"
    "AcroRd32"          = "Adobe Reader"
    "Photoshop"         = "Adobe Photoshop"
    "Illustrator"       = "Adobe Illustrator"
    "AfterFX"           = "Adobe After Effects"
    "Premiere Pro"      = "Adobe Premiere Pro"
    "GIMP"              = "GIMP"
    "OBS64"             = "OBS Studio"
    "Zoom"              = "Zoom"
    "ZoomIt"            = "ZoomIt"
    "Skype"             = "Skype"
    "thunderbird"       = "Thunderbird"
    "WinRAR"            = "WinRAR"
    "7zFM"              = "7-Zip"
    "filezilla"         = "FileZilla"
    "putty"             = "PuTTY"
    "GitHubDesktop"     = "GitHub Desktop"
    "Postman"           = "Postman"
    "idea64"            = "IntelliJ IDEA"
    "pycharm64"         = "PyCharm"
    "webstorm64"        = "WebStorm"
    "rider64"           = "Rider"
    "sublime_text"      = "Sublime Text"
    "atom"              = "Atom"
    "mintty"            = "Git Bash"
    "ConEmu64"          = "ConEmu"
    "Hyper"             = "Hyper Terminal"
    "Figma"             = "Figma"
    "Notion"            = "Notion"
    "Obsidian"          = "Obsidian"
    "Todoist"           = "Todoist"
    "Trello"            = "Trello"
    "Blender"           = "Blender"
    "Unity"             = "Unity Editor"
    "UE4Editor"         = "Unreal Engine"
    "AndroidStudio64"   = "Android Studio"
}

# ── App Category Mapping (friendly name → category) ──
$script:AppCategories = @{
    "Google Chrome"        = "Browsers"
    "Microsoft Edge"       = "Browsers"
    "Mozilla Firefox"      = "Browsers"
    "Brave Browser"        = "Browsers"
    "Opera Browser"        = "Browsers"
    "Internet Explorer"    = "Browsers"
    "Microsoft Word"       = "Productivity"
    "Microsoft Excel"      = "Productivity"
    "Microsoft PowerPoint" = "Productivity"
    "Microsoft OneNote"    = "Productivity"
    "Microsoft Outlook"    = "Productivity"
    "Notion"               = "Productivity"
    "Obsidian"             = "Productivity"
    "Todoist"              = "Productivity"
    "Trello"               = "Productivity"
    "Adobe Acrobat"        = "Productivity"
    "Adobe Reader"         = "Productivity"
    "Notepad"              = "Productivity"
    "Notepad++"            = "Productivity"
    "Calculator"           = "Productivity"
    "Visual Studio Code"   = "Development"
    "Visual Studio"        = "Development"
    "IntelliJ IDEA"        = "Development"
    "PyCharm"              = "Development"
    "WebStorm"             = "Development"
    "Rider"                = "Development"
    "Sublime Text"         = "Development"
    "Atom"                 = "Development"
    "Android Studio"       = "Development"
    "Postman"              = "Development"
    "GitHub Desktop"       = "Development"
    "FileZilla"            = "Development"
    "PuTTY"                = "Development"
    "Windows Terminal"     = "Development"
    "PowerShell"           = "Development"
    "Command Prompt"       = "Development"
    "Git Bash"             = "Development"
    "ConEmu"               = "Development"
    "Hyper Terminal"       = "Development"
    "Microsoft Teams"      = "Communication"
    "Discord"              = "Communication"
    "Slack"                = "Communication"
    "Telegram"             = "Communication"
    "WhatsApp"             = "Communication"
    "Zoom"                 = "Communication"
    "Skype"                = "Communication"
    "Thunderbird"          = "Communication"
    "Phone Link"           = "Communication"
    "Spotify"              = "Media"
    "VLC Media Player"     = "Media"
    "Windows Media Player" = "Media"
    "Movies & TV"          = "Media"
    "Photos"               = "Media"
    "OBS Studio"           = "Media"
    "Adobe Photoshop"      = "Creative"
    "Adobe Illustrator"    = "Creative"
    "Adobe After Effects"  = "Creative"
    "Adobe Premiere Pro"   = "Creative"
    "GIMP"                 = "Creative"
    "Figma"                = "Creative"
    "Blender"              = "Creative"
    "Paint"                = "Creative"
    "Steam"                = "Gaming"
    "Epic Games Launcher"  = "Gaming"
    "Xbox Game Bar"        = "Gaming"
    "Xbox"                 = "Gaming"
    "Unity Editor"         = "Gaming"
    "Unreal Engine"        = "Gaming"
    "File Explorer"        = "System"
    "Task Manager"         = "System"
    "Settings"             = "System"
    "Control Panel"        = "System"
    "Management Console"   = "System"
    "Registry Editor"      = "System"
    "Microsoft Store"      = "System"
    "Windows Search"       = "System"
    "Widgets"              = "System"
    "UWP App Host"         = "System"
    "Snipping Tool"        = "Utilities"
    "Snip & Sketch"        = "Utilities"
    "WinRAR"               = "Utilities"
    "7-Zip"                = "Utilities"
    "ZoomIt"               = "Utilities"
}

$script:CategoryIcons = @{
    "Browsers"      = [char]0xE774
    "Productivity"  = [char]0xE8A5
    "Development"   = [char]0xE943
    "Communication" = [char]0xE8BD
    "Media"         = [char]0xE8D6
    "Creative"      = [char]0xEA86
    "Gaming"        = [char]0xE7FC
    "System"        = [char]0xE770
    "Utilities"     = [char]0xE713
    "Other"         = [char]0xE71D
}

$script:CategoryColors = @{
    "Browsers"      = "#6C63FF"
    "Productivity"  = "#00C853"
    "Development"   = "#03DAC5"
    "Communication" = "#FFB300"
    "Media"         = "#FF6584"
    "Creative"      = "#E040FB"
    "Gaming"        = "#FF5722"
    "System"        = "#607D8B"
    "Utilities"     = "#8892B0"
    "Other"         = "#5A6078"
}

function Get-AppCategory {
    param([string]$AppName)
    if ($script:AppCategories.ContainsKey($AppName)) {
        return $script:AppCategories[$AppName]
    }
    return "Other"
}

function Get-FriendlyAppName {
    param([string]$ProcessName, [int]$ProcessId = 0)

    # Check cache first
    if ($script:AppNameCache.ContainsKey($ProcessName)) {
        return $script:AppNameCache[$ProcessName]
    }

    # Check known names map
    if ($script:KnownAppNames.ContainsKey($ProcessName)) {
        $friendly = $script:KnownAppNames[$ProcessName]
        $script:AppNameCache[$ProcessName] = $friendly
        return $friendly
    }

    # Try to get FileDescription from the process executable
    try {
        $proc = if ($ProcessId -gt 0) {
            Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        } else {
            Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($proc -and $proc.MainModule -and $proc.MainModule.FileVersionInfo) {
            $desc = $proc.MainModule.FileVersionInfo.FileDescription
            if ($desc -and $desc.Trim().Length -gt 1 -and $desc -ne $ProcessName) {
                $friendly = $desc.Trim()
                $script:AppNameCache[$ProcessName] = $friendly
                return $friendly
            }
            $productName = $proc.MainModule.FileVersionInfo.ProductName
            if ($productName -and $productName.Trim().Length -gt 1 -and $productName -ne $ProcessName) {
                $friendly = $productName.Trim()
                $script:AppNameCache[$ProcessName] = $friendly
                return $friendly
            }
        }
    } catch { }

    # Fallback: capitalize process name
    $friendly = (Get-Culture).TextInfo.ToTitleCase($ProcessName.ToLower())
    $script:AppNameCache[$ProcessName] = $friendly
    return $friendly
}

function Get-AppIcon {
    param([string]$ProcessName)
    $iconMap = @{
        "chrome"         = [char]0xE774
        "msedge"         = [char]0xE774
        "firefox"        = [char]0xE774
        "brave"          = [char]0xE774
        "Code"           = [char]0xE943
        "devenv"         = [char]0xE943
        "WINWORD"        = [char]0xE8A5
        "EXCEL"          = [char]0xE9F9
        "POWERPNT"       = [char]0xE8A5
        "OUTLOOK"        = [char]0xE715
        "Teams"          = [char]0xE716
        "Spotify"        = [char]0xE8D6
        "Discord"        = [char]0xE8BD
        "slack"          = [char]0xE8BD
        "explorer"       = [char]0xEC50
        "notepad"        = [char]0xE70F
        "WindowsTerminal"= [char]0xE756
        "powershell"     = [char]0xE756
        "cmd"            = [char]0xE756
    }
    if ($iconMap.ContainsKey($ProcessName)) { return $iconMap[$ProcessName] }
    return [char]0xE71E
}

# ══════════════════════════════════════════════════════════════════════
# WPF GUI - XAML Definition
# ══════════════════════════════════════════════════════════════════════

[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Digital Wellbeing"
        Width="1100" Height="720"
        MinWidth="900" MinHeight="600"
        WindowStartupLocation="CenterScreen"
        WindowStyle="None"
        AllowsTransparency="True"
        Background="Transparent"
        ResizeMode="CanResizeWithGrip">

    <Window.Resources>
        <!-- Color Palette -->
        <Color x:Key="PrimaryColor">#6C63FF</Color>
        <Color x:Key="PrimaryDarkColor">#5A52D5</Color>
        <Color x:Key="AccentColor">#FF6584</Color>
        <Color x:Key="SuccessColor">#00C853</Color>
        <Color x:Key="WarningColor">#FFB300</Color>
        <Color x:Key="DangerColor">#FF5252</Color>
        <Color x:Key="BgColor">#1A1A2E</Color>
        <Color x:Key="BgSecondaryColor">#16213E</Color>
        <Color x:Key="CardColor">#1F2940</Color>
        <Color x:Key="CardHoverColor">#263250</Color>
        <Color x:Key="TextPrimaryColor">#FFFFFF</Color>
        <Color x:Key="TextSecondaryColor">#8892B0</Color>
        <Color x:Key="BorderColor">#2D3A5C</Color>

        <SolidColorBrush x:Key="PrimaryBrush" Color="{StaticResource PrimaryColor}"/>
        <SolidColorBrush x:Key="PrimaryDarkBrush" Color="{StaticResource PrimaryDarkColor}"/>
        <SolidColorBrush x:Key="AccentBrush" Color="{StaticResource AccentColor}"/>
        <SolidColorBrush x:Key="SuccessBrush" Color="{StaticResource SuccessColor}"/>
        <SolidColorBrush x:Key="WarningBrush" Color="{StaticResource WarningColor}"/>
        <SolidColorBrush x:Key="DangerBrush" Color="{StaticResource DangerColor}"/>
        <SolidColorBrush x:Key="BgBrush" Color="{StaticResource BgColor}"/>
        <SolidColorBrush x:Key="BgSecondaryBrush" Color="{StaticResource BgSecondaryColor}"/>
        <SolidColorBrush x:Key="CardBrush" Color="{StaticResource CardColor}"/>
        <SolidColorBrush x:Key="CardHoverBrush" Color="{StaticResource CardHoverColor}"/>
        <SolidColorBrush x:Key="TextPrimaryBrush" Color="{StaticResource TextPrimaryColor}"/>
        <SolidColorBrush x:Key="TextSecondaryBrush" Color="{StaticResource TextSecondaryColor}"/>
        <SolidColorBrush x:Key="BorderBrush" Color="{StaticResource BorderColor}"/>

        <!-- Nav Button Style -->
        <Style x:Key="NavButtonStyle" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="{StaticResource TextSecondaryBrush}"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,12"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                CornerRadius="8" Margin="4,2" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource CardHoverBrush}"/>
                                <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Nav Button Active Style -->
        <Style x:Key="NavButtonActiveStyle" TargetType="Button" BasedOn="{StaticResource NavButtonStyle}">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
        </Style>

        <!-- Card Style -->
        <Style x:Key="CardStyle" TargetType="Border">
            <Setter Property="Background" Value="{StaticResource CardBrush}"/>
            <Setter Property="CornerRadius" Value="12"/>
            <Setter Property="Padding" Value="20"/>
            <Setter Property="Margin" Value="0,0,0,12"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
        </Style>

        <!-- Modern Button Style -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Segoe UI Semibold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="{StaticResource PrimaryDarkBrush}"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter TargetName="border" Property="Opacity" Value="0.5"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Danger Button Style -->
        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="{StaticResource DangerBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border x:Name="border" Background="{TemplateBinding Background}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="border" Property="Background" Value="#E04545"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- TextBox Style -->
        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="{StaticResource BgSecondaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontFamily" Value="Segoe UI"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ScrollViewer x:Name="PART_ContentHost" Focusable="False"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- PasswordBox Style -->
        <Style x:Key="ModernPasswordBox" TargetType="PasswordBox">
            <Setter Property="Background" Value="{StaticResource BgSecondaryBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource TextPrimaryBrush}"/>
            <Setter Property="BorderBrush" Value="{StaticResource BorderBrush}"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="PasswordBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8" Padding="{TemplateBinding Padding}">
                            <ScrollViewer x:Name="PART_ContentHost" Focusable="False"/>
                        </Border>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ScrollBar Style -->
        <Style TargetType="ScrollViewer">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollViewer">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>
                            <ScrollContentPresenter Grid.Column="0"/>
                            <ScrollBar Grid.Column="1" Name="PART_VerticalScrollBar"
                                       Value="{TemplateBinding VerticalOffset}"
                                       Maximum="{TemplateBinding ScrollableHeight}"
                                       ViewportSize="{TemplateBinding ViewportHeight}"
                                       Visibility="{TemplateBinding ComputedVerticalScrollBarVisibility}"
                                       Width="6" Opacity="0.3"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ToggleButton Style -->
        <Style x:Key="ToggleSwitch" TargetType="CheckBox">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="CheckBox">
                        <StackPanel Orientation="Horizontal">
                            <Grid Width="44" Height="24" Cursor="Hand">
                                <Border x:Name="track" Background="#3D4663" CornerRadius="12" Opacity="1"/>
                                <Border x:Name="thumb" Background="White" CornerRadius="10"
                                        Width="20" Height="20" HorizontalAlignment="Left" Margin="2,0,0,0"/>
                            </Grid>
                            <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
                        </StackPanel>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="track" Property="Background" Value="{StaticResource PrimaryBrush}"/>
                                <Setter TargetName="thumb" Property="HorizontalAlignment" Value="Right"/>
                                <Setter TargetName="thumb" Property="Margin" Value="0,0,2,0"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- ProgressBar Style -->
        <Style x:Key="ModernProgressBar" TargetType="ProgressBar">
            <Setter Property="Height" Value="8"/>
            <Setter Property="Background" Value="{StaticResource BorderBrush}"/>
            <Setter Property="Foreground" Value="{StaticResource PrimaryBrush}"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid>
                            <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="4"/>
                            <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="4"
                                    HorizontalAlignment="Left"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <!-- Main Window Border with Shadow -->
    <Border Background="{StaticResource BgBrush}" CornerRadius="16"
            BorderBrush="{StaticResource BorderBrush}" BorderThickness="1">
        <Border.Effect>
            <DropShadowEffect BlurRadius="20" ShadowDepth="0" Opacity="0.3" Color="Black"/>
        </Border.Effect>
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="40"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Title Bar -->
            <Border Grid.Row="0" Background="{StaticResource BgSecondaryBrush}"
                    CornerRadius="16,16,0,0" Name="TitleBar">
                <Grid>
                    <StackPanel Orientation="Horizontal" Margin="16,0,0,0" VerticalAlignment="Center">
                        <TextBlock Text="&#xE909;" FontFamily="Segoe MDL2 Assets" FontSize="14"
                                   Foreground="{StaticResource PrimaryBrush}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                        <TextBlock Text="Digital Wellbeing" FontFamily="Segoe UI Semibold" FontSize="13"
                                   Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
                        <TextBlock Text=" v1.0" FontSize="10"
                                   Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,0,8,0">
                        <Button Name="MinBtn" Content="&#xE921;" FontFamily="Segoe MDL2 Assets" FontSize="10"
                                Width="36" Height="32" Background="Transparent" Foreground="{StaticResource TextSecondaryBrush}"
                                BorderThickness="0" Cursor="Hand"/>
                        <Button Name="MaxBtn" Content="&#xE922;" FontFamily="Segoe MDL2 Assets" FontSize="10"
                                Width="36" Height="32" Background="Transparent" Foreground="{StaticResource TextSecondaryBrush}"
                                BorderThickness="0" Cursor="Hand"/>
                        <Button Name="CloseBtn" Content="&#xE8BB;" FontFamily="Segoe MDL2 Assets" FontSize="10"
                                Width="36" Height="32" Background="Transparent" Foreground="{StaticResource TextSecondaryBrush}"
                                BorderThickness="0" Cursor="Hand"/>
                    </StackPanel>
                </Grid>
            </Border>

            <!-- Main Content -->
            <Grid Grid.Row="1">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="220"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <!-- Sidebar Navigation -->
                <Border Grid.Column="0" Background="{StaticResource BgSecondaryBrush}"
                        CornerRadius="0,0,0,16" Padding="8,16">
                    <DockPanel>
                        <!-- User Profile Area -->
                        <StackPanel DockPanel.Dock="Top" Margin="8,0,8,20">
                            <Ellipse Width="56" Height="56" HorizontalAlignment="Center">
                                <Ellipse.Fill>
                                    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                        <GradientStop Color="{StaticResource PrimaryColor}" Offset="0"/>
                                        <GradientStop Color="{StaticResource AccentColor}" Offset="1"/>
                                    </LinearGradientBrush>
                                </Ellipse.Fill>
                            </Ellipse>
                            <TextBlock Text="&#xE77B;" FontFamily="Segoe MDL2 Assets" FontSize="24"
                                       Foreground="White" HorizontalAlignment="Center" Margin="0,-42,0,0"/>
                            <TextBlock Name="UserNameText" Text="User" FontSize="14" FontFamily="Segoe UI Semibold"
                                       Foreground="{StaticResource TextPrimaryBrush}" HorizontalAlignment="Center"
                                       Margin="0,20,0,2"/>
                            <TextBlock Name="ScreenTimeLabel" Text="0h 0m screen time today"
                                       FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"
                                       HorizontalAlignment="Center"/>
                        </StackPanel>

                        <!-- Nav Buttons -->
                        <StackPanel DockPanel.Dock="Top">
                            <TextBlock Text="MENU" FontSize="10" Foreground="{StaticResource TextSecondaryBrush}"
                                       FontFamily="Segoe UI Semibold" Margin="16,0,0,8"/>
                            <Button Name="NavDashboard" Style="{StaticResource NavButtonActiveStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE80F;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="Dashboard" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="NavApps" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE71E;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="App Usage" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="NavScreenTime" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE916;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="Screen Time" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="NavLimits" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE823;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="Time Limits" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="NavParental" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="Parental Controls" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>

                            <TextBlock Text="SYSTEM" FontSize="10" Foreground="{StaticResource TextSecondaryBrush}"
                                       FontFamily="Segoe UI Semibold" Margin="16,20,0,8"/>
                            <Button Name="NavSettings" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE713;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="Settings" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                            <Button Name="NavAbout" Style="{StaticResource NavButtonStyle}">
                                <StackPanel Orientation="Horizontal">
                                    <TextBlock Text="&#xE946;" FontFamily="Segoe MDL2 Assets" FontSize="15" Width="24" Margin="0,0,10,0"/>
                                    <TextBlock Text="About" VerticalAlignment="Center"/>
                                </StackPanel>
                            </Button>
                        </StackPanel>

                        <!-- Tracking Status -->
                        <StackPanel DockPanel.Dock="Bottom" VerticalAlignment="Bottom" Margin="8,0">
                            <Border Background="{StaticResource CardBrush}" CornerRadius="10" Padding="12,10"
                                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="1">
                                <StackPanel>
                                    <StackPanel Orientation="Horizontal">
                                        <Ellipse Name="TrackingIndicator" Width="8" Height="8" Fill="{StaticResource SuccessBrush}" Margin="0,0,8,0"/>
                                        <TextBlock Name="TrackingStatusText" Text="Tracking Active" FontSize="11"
                                                   Foreground="{StaticResource TextPrimaryBrush}"/>
                                    </StackPanel>
                                    <TextBlock Name="TrackingDetailText" Text="Monitoring apps..." FontSize="10"
                                               Foreground="{StaticResource TextSecondaryBrush}" Margin="16,4,0,0"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </DockPanel>
                </Border>

                <!-- Content Area -->
                <Border Grid.Column="1" Padding="24,16" CornerRadius="0,0,16,0">
                    <Grid>
                        <!-- Page: Dashboard -->
                        <ScrollViewer Name="PageDashboard" VerticalScrollBarVisibility="Auto">
                            <StackPanel>
                                <TextBlock Text="Dashboard" FontSize="24" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,4"/>
                                <TextBlock Name="DashboardDateText" Text="Today" FontSize="13"
                                           Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,20"/>

                                <!-- Stats Cards Row -->
                                <UniformGrid Columns="4" Margin="0,0,0,16">
                                    <!-- Screen Time Card -->
                                    <Border Style="{StaticResource CardStyle}" Margin="0,0,8,0">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <Border Name="StatIcon1Bg" CornerRadius="8" Padding="8" Margin="0,0,10,0">
                                                    <TextBlock Text="&#xE916;" FontFamily="Segoe MDL2 Assets"
                                                               Foreground="{StaticResource PrimaryBrush}" FontSize="16"/>
                                                </Border>
                                                <StackPanel VerticalAlignment="Center">
                                                    <TextBlock Text="Screen Time" FontSize="11"
                                                               Foreground="{StaticResource TextSecondaryBrush}"/>
                                                    <TextBlock Name="DashScreenTime" Text="0h 0m" FontSize="20"
                                                               FontFamily="Segoe UI Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                    <!-- Apps Used Card -->
                                    <Border Style="{StaticResource CardStyle}" Margin="4,0,4,0">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <Border Name="StatIcon2Bg" CornerRadius="8" Padding="8" Margin="0,0,10,0">
                                                    <TextBlock Text="&#xE71E;" FontFamily="Segoe MDL2 Assets"
                                                               Foreground="{StaticResource SuccessBrush}" FontSize="16"/>
                                                </Border>
                                                <StackPanel VerticalAlignment="Center">
                                                    <TextBlock Text="Apps Used" FontSize="11"
                                                               Foreground="{StaticResource TextSecondaryBrush}"/>
                                                    <TextBlock Name="DashAppsCount" Text="0" FontSize="20"
                                                               FontFamily="Segoe UI Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                    <!-- Notifications Card -->
                                    <Border Style="{StaticResource CardStyle}" Margin="4,0,4,0">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <Border Name="StatIcon3Bg" CornerRadius="8" Padding="8" Margin="0,0,10,0">
                                                    <TextBlock Text="&#xEA8F;" FontFamily="Segoe MDL2 Assets"
                                                               Foreground="{StaticResource WarningBrush}" FontSize="16"/>
                                                </Border>
                                                <StackPanel VerticalAlignment="Center">
                                                    <TextBlock Text="Limits Set" FontSize="11"
                                                               Foreground="{StaticResource TextSecondaryBrush}"/>
                                                    <TextBlock Name="DashLimitsCount" Text="0" FontSize="20"
                                                               FontFamily="Segoe UI Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                    <!-- Parental Status Card -->
                                    <Border Style="{StaticResource CardStyle}" Margin="8,0,0,0">
                                        <StackPanel>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <Border Name="StatIcon4Bg" CornerRadius="8" Padding="8" Margin="0,0,10,0">
                                                    <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets"
                                                               Foreground="{StaticResource AccentBrush}" FontSize="16"/>
                                                </Border>
                                                <StackPanel VerticalAlignment="Center">
                                                    <TextBlock Text="Parental" FontSize="11"
                                                               Foreground="{StaticResource TextSecondaryBrush}"/>
                                                    <TextBlock Name="DashParentalStatus" Text="Off" FontSize="20"
                                                               FontFamily="Segoe UI Bold" Foreground="{StaticResource TextPrimaryBrush}"/>
                                                </StackPanel>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </UniformGrid>

                                <!-- Top Apps and Usage Chart -->
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>

                                    <!-- Top Apps -->
                                    <Border Grid.Column="0" Style="{StaticResource CardStyle}" Margin="0,0,8,0">
                                        <StackPanel>
                                            <TextBlock Text="Top Applications" FontSize="15" FontFamily="Segoe UI Semibold"
                                                       Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                            <StackPanel Name="DashTopApps">
                                                <TextBlock Text="No data yet - start using your apps!"
                                                           Foreground="{StaticResource TextSecondaryBrush}"
                                                           FontSize="12" FontStyle="Italic"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Usage Chart (Bar Chart) -->
                                    <Border Grid.Column="1" Style="{StaticResource CardStyle}" Margin="8,0,0,0">
                                        <StackPanel>
                                            <TextBlock Text="Usage Breakdown" FontSize="15" FontFamily="Segoe UI Semibold"
                                                       Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                            <Canvas Name="DashChart" Height="200" ClipToBounds="True">
                                                <TextBlock Text="Collecting data..." Canvas.Left="50" Canvas.Top="90"
                                                           Foreground="{StaticResource TextSecondaryBrush}" FontStyle="Italic"/>
                                            </Canvas>
                                        </StackPanel>
                                    </Border>
                                </Grid>

                                <!-- Most Used by Category -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Most Used by Category" FontSize="15" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <StackPanel Name="DashCategoryPanel">
                                            <TextBlock Text="Collecting category data..."
                                                       Foreground="{StaticResource TextSecondaryBrush}"
                                                       FontSize="12" FontStyle="Italic"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>

                                <!-- Recent Activity -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Currently Running Applications" FontSize="15" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <StackPanel Name="DashRunningApps">
                                            <TextBlock Text="Scanning for running applications..."
                                                       Foreground="{StaticResource TextSecondaryBrush}"
                                                       FontSize="12" FontStyle="Italic"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: App Usage -->
                        <ScrollViewer Name="PageApps" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel>
                                <Grid Margin="0,0,0,20">
                                    <TextBlock Text="Application Usage" FontSize="24" FontFamily="Segoe UI Bold"
                                               Foreground="{StaticResource TextPrimaryBrush}" VerticalAlignment="Center"/>
                                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                                        <TextBox Name="AppSearchBox" Width="200" Style="{StaticResource ModernTextBox}"
                                                 FontSize="12" Margin="0,0,8,0"/>
                                        <Button Name="RefreshAppsBtn" Style="{StaticResource ModernButton}" Padding="12,8">
                                            <StackPanel Orientation="Horizontal">
                                                <TextBlock Text="&#xE72C;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                <TextBlock Text="Refresh"/>
                                            </StackPanel>
                                        </Button>
                                    </StackPanel>
                                </Grid>

                                <!-- Apps Header -->
                                <Border Background="{StaticResource BgSecondaryBrush}" CornerRadius="8,8,0,0" Padding="16,10"
                                        BorderBrush="{StaticResource BorderBrush}" BorderThickness="1,1,1,0">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="40"/>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="150"/>
                                            <ColumnDefinition Width="100"/>
                                            <ColumnDefinition Width="100"/>
                                            <ColumnDefinition Width="80"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Grid.Column="0" Text="" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                        <TextBlock Grid.Column="1" Text="Application" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" FontFamily="Segoe UI Semibold"/>
                                        <TextBlock Grid.Column="2" Text="Window Title" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" FontFamily="Segoe UI Semibold"/>
                                        <TextBlock Grid.Column="3" Text="Usage Time" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" FontFamily="Segoe UI Semibold"/>
                                        <TextBlock Grid.Column="4" Text="Memory" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" FontFamily="Segoe UI Semibold"/>
                                        <TextBlock Grid.Column="5" Text="Status" FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" FontFamily="Segoe UI Semibold"/>
                                    </Grid>
                                </Border>

                                <!-- Apps List -->
                                <Border Style="{StaticResource CardStyle}" CornerRadius="0,0,8,8" Margin="0">
                                    <StackPanel Name="AppsListPanel">
                                        <TextBlock Text="Loading applications..."
                                                   Foreground="{StaticResource TextSecondaryBrush}"
                                                   FontSize="12" FontStyle="Italic" Margin="0,10"/>
                                    </StackPanel>
                                </Border>

                                <!-- Third-Party Apps Section -->
                                <TextBlock Text="Third-Party Application Usage" FontSize="18" FontFamily="Segoe UI Semibold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,20,0,12"/>
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel Name="ThirdPartyAppsPanel">
                                        <TextBlock Text="Detecting third-party applications..."
                                                   Foreground="{StaticResource TextSecondaryBrush}"
                                                   FontSize="12" FontStyle="Italic"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: Screen Time -->
                        <ScrollViewer Name="PageScreenTime" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Screen Time" FontSize="24" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,4"/>
                                <TextBlock Text="Monitor your daily and weekly screen usage"
                                           FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,20"/>

                                <!-- Today's Summary -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Today's Screen Time" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="*"/>
                                            </Grid.ColumnDefinitions>
                                            <StackPanel Grid.Column="0" HorizontalAlignment="Center">
                                                <TextBlock Name="STTotalTime" Text="0h 0m" FontSize="32" FontFamily="Segoe UI Bold"
                                                           Foreground="{StaticResource PrimaryBrush}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Total Time" FontSize="12"
                                                           Foreground="{StaticResource TextSecondaryBrush}" HorizontalAlignment="Center"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="1" HorizontalAlignment="Center">
                                                <TextBlock Name="STSessionTime" Text="0h 0m" FontSize="32" FontFamily="Segoe UI Bold"
                                                           Foreground="{StaticResource SuccessBrush}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Current Session" FontSize="12"
                                                           Foreground="{StaticResource TextSecondaryBrush}" HorizontalAlignment="Center"/>
                                            </StackPanel>
                                            <StackPanel Grid.Column="2" HorizontalAlignment="Center">
                                                <TextBlock Name="STAppsUsed" Text="0" FontSize="32" FontFamily="Segoe UI Bold"
                                                           Foreground="{StaticResource WarningBrush}" HorizontalAlignment="Center"/>
                                                <TextBlock Text="Apps Used" FontSize="12"
                                                           Foreground="{StaticResource TextSecondaryBrush}" HorizontalAlignment="Center"/>
                                            </StackPanel>
                                        </Grid>
                                    </StackPanel>
                                </Border>

                                <!-- Weekly Chart -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="This Week's Usage" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <Canvas Name="WeeklyChart" Height="220" ClipToBounds="True"/>
                                    </StackPanel>
                                </Border>

                                <!-- Hourly Breakdown -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Hourly Activity" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <Canvas Name="HourlyChart" Height="160" ClipToBounds="True"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: Time Limits -->
                        <ScrollViewer Name="PageLimits" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Time Limits" FontSize="24" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,4"/>
                                <TextBlock Text="Set daily usage limits for individual applications"
                                           FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,20"/>

                                <!-- Add Limit -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Add New Limit" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <Grid>
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="150"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>
                                            <TextBox Name="LimitAppName" Grid.Column="0" Style="{StaticResource ModernTextBox}"
                                                     Margin="0,0,8,0"/>
                                            <TextBox Name="LimitMinutes" Grid.Column="1" Style="{StaticResource ModernTextBox}"
                                                     Margin="0,0,8,0"/>
                                            <Button Name="AddLimitBtn" Grid.Column="2" Style="{StaticResource ModernButton}">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="&#xE710;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                    <TextBlock Text="Add Limit"/>
                                                </StackPanel>
                                            </Button>
                                        </Grid>
                                        <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                                            <TextBlock Text="App name (e.g., Google Chrome, Discord, Notepad)"
                                                       FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,30,0"/>
                                            <TextBlock Text="Daily limit in minutes"
                                                       FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>

                                <!-- Current Limits -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Active Limits" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <StackPanel Name="LimitsListPanel">
                                            <TextBlock Text="No limits set yet. Add a limit above to get started."
                                                       Foreground="{StaticResource TextSecondaryBrush}"
                                                       FontSize="12" FontStyle="Italic"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>

                                <!-- Quick Set Limits -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Quick Set - Popular Apps" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <WrapPanel Name="QuickLimitsPanel">
                                        </WrapPanel>
                                    </StackPanel>
                                </Border>

                                <!-- Running Apps List -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Running Applications" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,4"/>
                                        <TextBlock Text="Click an app to set a time limit"
                                                   FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,12"/>
                                        <StackPanel Name="LimitsAppListPanel">
                                            <TextBlock Text="Loading running apps..."
                                                       Foreground="{StaticResource TextSecondaryBrush}"
                                                       FontSize="12" FontStyle="Italic"/>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: Parental Controls -->
                        <ScrollViewer Name="PageParental" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Parental Controls" FontSize="24" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,4"/>
                                <TextBlock Text="Manage and restrict device usage for children"
                                           FontSize="13" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,20"/>

                                <!-- PIN Setup / Lock Screen -->
                                <Border Name="ParentalLockScreen" Style="{StaticResource CardStyle}" Visibility="Collapsed">
                                    <StackPanel HorizontalAlignment="Center" Margin="0,30">
                                        <TextBlock Text="&#xE72E;" FontFamily="Segoe MDL2 Assets" FontSize="48"
                                                   Foreground="{StaticResource PrimaryBrush}" HorizontalAlignment="Center" Margin="0,0,0,16"/>
                                        <TextBlock Text="Enter PIN to access Parental Controls" FontSize="16"
                                                   Foreground="{StaticResource TextPrimaryBrush}" HorizontalAlignment="Center" Margin="0,0,0,20"/>
                                        <PasswordBox Name="PinEntryBox" Style="{StaticResource ModernPasswordBox}"
                                                     Width="200" MaxLength="6" HorizontalAlignment="Center" Margin="0,0,0,16"/>
                                        <Button Name="PinUnlockBtn" Style="{StaticResource ModernButton}"
                                                Content="Unlock" HorizontalAlignment="Center" Width="200"/>
                                        <TextBlock Name="PinErrorText" Text="" Foreground="{StaticResource DangerBrush}"
                                                   FontSize="12" HorizontalAlignment="Center" Margin="0,8,0,0"/>
                                    </StackPanel>
                                </Border>

                                <!-- Parental Content (hidden behind PIN) -->
                                <StackPanel Name="ParentalContent">
                                    <!-- Enable/Disable -->
                                    <Border Style="{StaticResource CardStyle}">
                                        <StackPanel>
                                            <Grid>
                                                <StackPanel>
                                                    <TextBlock Text="Parental Controls" FontSize="16" FontFamily="Segoe UI Semibold"
                                                               Foreground="{StaticResource TextPrimaryBrush}"/>
                                                    <TextBlock Text="Enable to restrict and monitor device usage"
                                                               FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>
                                                </StackPanel>
                                                <CheckBox Name="ParentalEnabledToggle" Style="{StaticResource ToggleSwitch}"
                                                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                            </Grid>
                                        </StackPanel>
                                    </Border>

                                    <!-- PIN Setup -->
                                    <Border Style="{StaticResource CardStyle}">
                                        <StackPanel>
                                            <TextBlock Text="PIN Protection" FontSize="16" FontFamily="Segoe UI Semibold"
                                                       Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <TextBlock Text="Set PIN (4-6 digits):" FontSize="13"
                                                           Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                           Margin="0,0,12,0" Width="140"/>
                                                <PasswordBox Name="SetPinBox" Style="{StaticResource ModernPasswordBox}"
                                                             Width="150" MaxLength="6" Margin="0,0,8,0"/>
                                                <Button Name="SetPinBtn" Style="{StaticResource ModernButton}" Content="Set PIN"/>
                                            </StackPanel>
                                            <TextBlock Name="PinStatusText" Text="No PIN set" FontSize="11"
                                                       Foreground="{StaticResource TextSecondaryBrush}" Margin="0,4,0,0"/>

                                            <!-- Change PIN Section -->
                                            <Border Name="ChangePinSection" Margin="0,16,0,0" Padding="12"
                                                    Background="{StaticResource BgSecondaryBrush}" CornerRadius="8"
                                                    BorderBrush="{StaticResource BorderBrush}" BorderThickness="1"
                                                    Visibility="Collapsed">
                                                <StackPanel>
                                                    <TextBlock Text="Change PIN" FontSize="14" FontFamily="Segoe UI Semibold"
                                                               Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,10"/>
                                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                        <TextBlock Text="Current PIN:" FontSize="12"
                                                                   Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                                   Width="100"/>
                                                        <PasswordBox Name="OldPinBox" Style="{StaticResource ModernPasswordBox}"
                                                                     Width="150" MaxLength="6"/>
                                                    </StackPanel>
                                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                        <TextBlock Text="New PIN:" FontSize="12"
                                                                   Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                                   Width="100"/>
                                                        <PasswordBox Name="NewPinBox" Style="{StaticResource ModernPasswordBox}"
                                                                     Width="150" MaxLength="6"/>
                                                    </StackPanel>
                                                    <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                        <TextBlock Text="Confirm PIN:" FontSize="12"
                                                                   Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                                   Width="100"/>
                                                        <PasswordBox Name="ConfirmPinBox" Style="{StaticResource ModernPasswordBox}"
                                                                     Width="150" MaxLength="6"/>
                                                    </StackPanel>
                                                    <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                                                        <Button Name="SaveNewPinBtn" Style="{StaticResource ModernButton}"
                                                                Content="Save New PIN" Margin="0,0,8,0"/>
                                                        <Button Name="CancelChangePinBtn" Style="{StaticResource DangerButton}"
                                                                Content="Cancel"/>
                                                    </StackPanel>
                                                    <TextBlock Name="ChangePinErrorText" Text="" FontSize="11"
                                                               Foreground="{StaticResource DangerBrush}" Margin="0,6,0,0"/>
                                                </StackPanel>
                                            </Border>
                                            <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                                <Button Name="ChangePinBtn" Style="{StaticResource ModernButton}"
                                                        Content="Change PIN" Margin="0,0,8,0"
                                                        Visibility="Collapsed"/>
                                                <Button Name="ResetPinBtn" Style="{StaticResource DangerButton}"
                                                        Content="Reset PIN"
                                                        Visibility="Collapsed"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Block Apps -->
                                    <Border Style="{StaticResource CardStyle}">
                                        <StackPanel>
                                            <TextBlock Text="Block Applications" FontSize="16" FontFamily="Segoe UI Semibold"
                                                       Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,12">
                                                <TextBox Name="BlockAppName" Style="{StaticResource ModernTextBox}"
                                                         Width="300" Margin="0,0,8,0"/>
                                                <Button Name="BlockAppBtn" Style="{StaticResource DangerButton}">
                                                    <StackPanel Orientation="Horizontal">
                                                        <TextBlock Text="&#xE711;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                        <TextBlock Text="Block App"/>
                                                    </StackPanel>
                                                </Button>
                                            </StackPanel>
                                            <TextBlock Text="Enter process name to block (e.g., chrome, discord, steam)"
                                                       FontSize="11" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,12"/>
                                            <StackPanel Name="BlockedAppsPanel">
                                                <TextBlock Text="No apps blocked"
                                                           Foreground="{StaticResource TextSecondaryBrush}"
                                                           FontSize="12" FontStyle="Italic"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>

                                    <!-- Bedtime Schedule -->
                                    <Border Style="{StaticResource CardStyle}">
                                        <StackPanel>
                                            <Grid Margin="0,0,0,12">
                                                <TextBlock Text="Bedtime Schedule" FontSize="16" FontFamily="Segoe UI Semibold"
                                                           Foreground="{StaticResource TextPrimaryBrush}"/>
                                                <CheckBox Name="BedtimeToggle" Style="{StaticResource ToggleSwitch}"
                                                          HorizontalAlignment="Right"/>
                                            </Grid>
                                            <TextBlock Text="Restrict device usage during bedtime hours"
                                                       FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,16"/>
                                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                                <TextBlock Text="Start Time:" FontSize="13"
                                                           Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                           Width="80"/>
                                                <TextBox Name="BedtimeStartBox" Style="{StaticResource ModernTextBox}"
                                                         Text="22:00" Width="100" Margin="0,0,20,0"/>
                                                <TextBlock Text="End Time:" FontSize="13"
                                                           Foreground="{StaticResource TextSecondaryBrush}" VerticalAlignment="Center"
                                                           Width="80"/>
                                                <TextBox Name="BedtimeEndBox" Style="{StaticResource ModernTextBox}"
                                                         Text="07:00" Width="100"/>
                                            </StackPanel>
                                            <Button Name="SaveBedtimeBtn" Style="{StaticResource ModernButton}"
                                                    Content="Save Schedule" HorizontalAlignment="Left" Margin="0,12,0,0"/>
                                        </StackPanel>
                                    </Border>

                                    <!-- Usage Report -->
                                    <Border Style="{StaticResource CardStyle}">
                                        <StackPanel>
                                            <TextBlock Text="Usage Report" FontSize="16" FontFamily="Segoe UI Semibold"
                                                       Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,12"/>
                                            <Button Name="GenerateReportBtn" Style="{StaticResource ModernButton}"
                                                    HorizontalAlignment="Left" Margin="0,0,0,12">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="&#xE9F9;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                    <TextBlock Text="Generate Weekly Report"/>
                                                </StackPanel>
                                            </Button>
                                            <StackPanel Name="ReportPanel">
                                                <TextBlock Text="Click 'Generate Weekly Report' to create a usage summary."
                                                           Foreground="{StaticResource TextSecondaryBrush}"
                                                           FontSize="12" FontStyle="Italic"/>
                                            </StackPanel>
                                        </StackPanel>
                                    </Border>
                                </StackPanel>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: Settings -->
                        <ScrollViewer Name="PageSettings" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel>
                                <TextBlock Text="Settings" FontSize="24" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,20"/>

                                <!-- General Settings -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="General" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1"
                                                Padding="0,0,0,12" Margin="0,0,0,12">
                                            <Grid>
                                                <StackPanel>
                                                    <TextBlock Text="Enable Tracking" FontSize="13"
                                                               Foreground="{StaticResource TextPrimaryBrush}"/>
                                                    <TextBlock Text="Track application usage in the background"
                                                               FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                                </StackPanel>
                                                <CheckBox Name="TrackingToggle" Style="{StaticResource ToggleSwitch}"
                                                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1"
                                                Padding="0,0,0,12" Margin="0,0,0,12">
                                            <Grid>
                                                <StackPanel>
                                                    <TextBlock Text="Enable Notifications" FontSize="13"
                                                               Foreground="{StaticResource TextPrimaryBrush}"/>
                                                    <TextBlock Text="Show alerts for time limits and reminders"
                                                               FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                                </StackPanel>
                                                <CheckBox Name="NotificationsToggle" Style="{StaticResource ToggleSwitch}"
                                                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1"
                                                Padding="0,0,0,12" Margin="0,0,0,12">
                                            <Grid>
                                                <StackPanel>
                                                    <TextBlock Text="Minimize to System Tray" FontSize="13"
                                                               Foreground="{StaticResource TextPrimaryBrush}"/>
                                                    <TextBlock Text="Keep running in the background when closed"
                                                               FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                                </StackPanel>
                                                <CheckBox Name="TrayToggle" Style="{StaticResource ToggleSwitch}"
                                                          HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                            </Grid>
                                        </Border>
                                        <Grid Margin="0,0,0,12">
                                            <StackPanel>
                                                <TextBlock Text="Start with Windows" FontSize="13"
                                                           Foreground="{StaticResource TextPrimaryBrush}"/>
                                                <TextBlock Text="Auto-start and run in background on Windows login"
                                                           FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                            </StackPanel>
                                            <CheckBox Name="StartupToggle" Style="{StaticResource ToggleSwitch}"
                                                      HorizontalAlignment="Right" VerticalAlignment="Center"/>
                                        </Grid>
                                    </StackPanel>
                                </Border>

                                <!-- Theme Settings -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Appearance" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <Grid Margin="0,0,0,12">
                                            <StackPanel>
                                                <TextBlock Text="Theme" FontSize="13"
                                                           Foreground="{StaticResource TextPrimaryBrush}"/>
                                                <TextBlock Text="Choose Dark, Light, or follow Windows system setting"
                                                           FontSize="11" Foreground="{StaticResource TextSecondaryBrush}"/>
                                            </StackPanel>
                                            <ComboBox Name="ThemeComboBox" HorizontalAlignment="Right" VerticalAlignment="Center"
                                                      Width="160" FontSize="13">
                                                <ComboBoxItem Content="Dark" IsSelected="True"/>
                                                <ComboBoxItem Content="Light"/>
                                                <ComboBoxItem Content="Windows Default"/>
                                            </ComboBox>
                                        </Grid>
                                    </StackPanel>
                                </Border>

                                <!-- Data Management -->
                                <Border Style="{StaticResource CardStyle}">
                                    <StackPanel>
                                        <TextBlock Text="Data Management" FontSize="16" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,16"/>
                                        <TextBlock Name="DataPathText" Text="" FontSize="12"
                                                   Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,12"/>
                                        <StackPanel Orientation="Horizontal">
                                            <Button Name="ExportDataBtn" Style="{StaticResource ModernButton}" Margin="0,0,8,0">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="&#xEDE1;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                    <TextBlock Text="Export Data"/>
                                                </StackPanel>
                                            </Button>
                                            <Button Name="ClearDataBtn" Style="{StaticResource DangerButton}">
                                                <StackPanel Orientation="Horizontal">
                                                    <TextBlock Text="&#xE74D;" FontFamily="Segoe MDL2 Assets" FontSize="12" Margin="0,0,6,0"/>
                                                    <TextBlock Text="Clear All Data"/>
                                                </StackPanel>
                                            </Button>
                                        </StackPanel>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>

                        <!-- Page: About -->
                        <ScrollViewer Name="PageAbout" VerticalScrollBarVisibility="Auto" Visibility="Collapsed">
                            <StackPanel HorizontalAlignment="Center" Margin="0,40,0,0">
                                <Ellipse Width="80" Height="80" HorizontalAlignment="Center" Margin="0,0,0,20">
                                    <Ellipse.Fill>
                                        <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                                            <GradientStop Color="{StaticResource PrimaryColor}" Offset="0"/>
                                            <GradientStop Color="{StaticResource AccentColor}" Offset="1"/>
                                        </LinearGradientBrush>
                                    </Ellipse.Fill>
                                </Ellipse>
                                <TextBlock Text="&#xE909;" FontFamily="Segoe MDL2 Assets" FontSize="36"
                                           Foreground="White" HorizontalAlignment="Center" Margin="0,-58,0,0"/>
                                <TextBlock Text="Digital Wellbeing" FontSize="28" FontFamily="Segoe UI Bold"
                                           Foreground="{StaticResource TextPrimaryBrush}" HorizontalAlignment="Center" Margin="0,18,0,4"/>
                                <TextBlock Text="Version 1.0.0" FontSize="14"
                                           Foreground="{StaticResource TextSecondaryBrush}" HorizontalAlignment="Center" Margin="0,0,0,20"/>

                                <Border Style="{StaticResource CardStyle}" MaxWidth="500">
                                    <StackPanel>
                                        <TextBlock Text="A comprehensive digital wellness solution for Windows, built entirely with PowerShell and WPF."
                                                   FontSize="13" Foreground="{StaticResource TextSecondaryBrush}"
                                                   TextWrapping="Wrap" TextAlignment="Center" Margin="0,0,0,16"/>

                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1"
                                                Padding="0,0,0,12" Margin="0,0,0,12">
                                            <StackPanel>
                                                <TextBlock Text="Features" FontSize="15" FontFamily="Segoe UI Semibold"
                                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                                <TextBlock FontSize="12" Foreground="{StaticResource TextSecondaryBrush}" TextWrapping="Wrap">
                                                    <Run Text="&#x2022; Real-time application usage tracking"/><LineBreak/>
                                                    <Run Text="&#x2022; Screen time monitoring with charts"/><LineBreak/>
                                                    <Run Text="&#x2022; Per-app time limits with notifications"/><LineBreak/>
                                                    <Run Text="&#x2022; Parental controls with PIN protection"/><LineBreak/>
                                                    <Run Text="&#x2022; App blocking and bedtime schedules"/><LineBreak/>
                                                    <Run Text="&#x2022; Weekly usage reports"/><LineBreak/>
                                                    <Run Text="&#x2022; Data export functionality"/>
                                                </TextBlock>
                                            </StackPanel>
                                        </Border>

                                        <Border BorderBrush="{StaticResource BorderBrush}" BorderThickness="0,0,0,1"
                                                Padding="0,0,0,12" Margin="0,0,0,12">
                                            <StackPanel>
                                                <TextBlock Text="Author" FontSize="15" FontFamily="Segoe UI Semibold"
                                                           Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                                <TextBlock Text="Created by Sumit (HackWithSumit)" FontSize="12"
                                                           Foreground="{StaticResource TextSecondaryBrush}" Margin="0,0,0,4"/>
                                                <TextBlock Text="github.com/HackWithSumit" FontSize="12"
                                                           Foreground="{StaticResource PrimaryBrush}"/>
                                            </StackPanel>
                                        </Border>

                                        <TextBlock Text="License" FontSize="15" FontFamily="Segoe UI Semibold"
                                                   Foreground="{StaticResource TextPrimaryBrush}" Margin="0,0,0,8"/>
                                        <TextBlock Text="MIT License - Free and Open Source" FontSize="12"
                                                   Foreground="{StaticResource TextSecondaryBrush}"/>
                                    </StackPanel>
                                </Border>
                            </StackPanel>
                        </ScrollViewer>
                    </Grid>
                </Border>
            </Grid>
        </Grid>
    </Border>
</Window>
"@

# ══════════════════════════════════════════════════════════════════════
# WPF WINDOW CREATION & EVENT HANDLING
# ══════════════════════════════════════════════════════════════════════

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get all named elements (only match direct Name attributes, not x:Name in templates)
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    $name = $_.GetAttribute("Name")
    if ($name) {
        $element = $window.FindName($name)
        if ($element) {
            Set-Variable -Name $name -Value $element -Scope Script
        }
    }
}

# ── Set initial stat icon backgrounds ──
$converter = [System.Windows.Media.BrushConverter]::new()
try {
    $StatIcon1Bg.Background = $converter.ConvertFrom("#2D1F6B")
    $StatIcon2Bg.Background = $converter.ConvertFrom("#1B3A2A")
    $StatIcon3Bg.Background = $converter.ConvertFrom("#3A2A1B")
    $StatIcon4Bg.Background = $converter.ConvertFrom("#3A1B2A")
} catch { }

# ── Title Bar Drag ──
$TitleBar.Add_MouseLeftButtonDown({
    $window.DragMove()
})

# ── Window Controls ──
$MinBtn.Add_Click({ $window.WindowState = 'Minimized' })
$MaxBtn.Add_Click({
    if ($window.WindowState -eq 'Maximized') {
        $window.WindowState = 'Normal'
    } else {
        $window.WindowState = 'Maximized'
    }
})
$CloseBtn.Add_Click({
    if (-not $script:ForceClose) {
        $window.WindowState = 'Minimized'
        $window.ShowInTaskbar = $false
        $script:TrayIcon.ShowBalloonTip(3000, "Digital Wellbeing", "Running in background. Click tray icon to open.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# Intercept window closing (X button, Alt+F4) to minimize to tray
$window.Add_Closing({
    param($sender, $e)
    if (-not $script:ForceClose) {
        $e.Cancel = $true
        $window.WindowState = 'Minimized'
        $window.ShowInTaskbar = $false
        $script:TrayIcon.ShowBalloonTip(3000, "Digital Wellbeing", "Running in background. Click tray icon to open.", [System.Windows.Forms.ToolTipIcon]::Info)
    }
})

# ── Navigation ──
$script:NavButtons = @($NavDashboard, $NavApps, $NavScreenTime, $NavLimits, $NavParental, $NavSettings, $NavAbout)
$script:Pages = @($PageDashboard, $PageApps, $PageScreenTime, $PageLimits, $PageParental, $PageSettings, $PageAbout)

function Switch-Page {
    param([int]$Index)

    for ($i = 0; $i -lt $script:Pages.Count; $i++) {
        $script:Pages[$i].Visibility = if ($i -eq $Index) { 'Visible' } else { 'Collapsed' }
        $script:NavButtons[$i].Style = $window.FindResource(
            $(if ($i -eq $Index) { 'NavButtonActiveStyle' } else { 'NavButtonStyle' })
        )
    }

    # Fix nav button foreground colors for current theme
    if ($script:CurrentTheme) {
        $converter = [System.Windows.Media.BrushConverter]::new()
        for ($i = 0; $i -lt $script:NavButtons.Count; $i++) {
            $fgBrush = if ($i -eq $Index) {
                $converter.ConvertFrom("#FFFFFF")
            } else {
                $converter.ConvertFrom($script:CurrentTheme['TextSecondaryColor'])
            }
            $script:NavButtons[$i].Foreground = $fgBrush
            # Explicitly walk button visual tree to update child TextBlocks
            function Set-ChildTextForeground {
                param($el, $brush)
                if ($el -is [System.Windows.Controls.TextBlock]) {
                    $el.Foreground = $brush
                }
                $cnt = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
                for ($k = 0; $k -lt $cnt; $k++) {
                    $ch = [System.Windows.Media.VisualTreeHelper]::GetChild($el, $k)
                    Set-ChildTextForeground $ch $brush
                }
            }
            try { Set-ChildTextForeground $script:NavButtons[$i] $fgBrush } catch { }
        }
    }

    # Refresh page content
    switch ($Index) {
        0 { Update-Dashboard }
        1 { Update-AppsList }
        2 { Update-ScreenTime }
        3 { Update-LimitsList; Update-LimitsAppList }
        4 { Update-ParentalPage }
    }
}

$NavDashboard.Add_Click({ Switch-Page 0 })
$NavApps.Add_Click({ Switch-Page 1 })
$NavScreenTime.Add_Click({ Switch-Page 2 })
$NavLimits.Add_Click({ Switch-Page 3 })
$NavParental.Add_Click({ Switch-Page 4 })
$NavSettings.Add_Click({ Switch-Page 5 })
$NavAbout.Add_Click({ Switch-Page 6 })

# ── Dashboard Update ──
function Update-Dashboard {
    $totalSec = $script:TotalScreenTimeToday
    $hours = [math]::Floor($totalSec / 3600)
    $mins = [math]::Floor(($totalSec % 3600) / 60)
    $DashScreenTime.Text = "${hours}h ${mins}m"
    $ScreenTimeLabel.Text = "${hours}h ${mins}m screen time today"
    $DashAppsCount.Text = $script:CurrentAppUsage.Count.ToString()
    $DashDateText = $window.FindName("DashboardDateText")
    if ($DashDateText) { $DashDateText.Text = (Get-Date).ToString("dddd, MMMM dd, yyyy") }

    # Limits count
    $limitsCount = 0
    if ($script:Limits.PSObject) {
        $limitsCount = @($script:Limits.PSObject.Properties).Count
    }
    $DashLimitsCount.Text = $limitsCount.ToString()

    # Parental status
    $DashParentalStatus.Text = if ($script:ParentalConfig.Enabled) { "On" } else { "Off" }

    # Top Apps
    $DashTopApps.Children.Clear()
    $sortedApps = $script:CurrentAppUsage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 5
    $maxUsage = ($sortedApps | Measure-Object -Property Value -Maximum).Maximum
    if (-not $maxUsage) { $maxUsage = 1 }

    foreach ($app in $sortedApps) {
        $appBorder = New-Object System.Windows.Controls.Border
        $appBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)
        $appBorder.BorderBrush = $window.FindResource("BorderBrush")
        $appBorder.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $appBorder.Padding = [System.Windows.Thickness]::new(0, 0, 0, 8)

        $grid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition
        $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition
        $col2.Width = [System.Windows.GridLength]::new(80)
        $grid.ColumnDefinitions.Add($col1)
        $grid.ColumnDefinitions.Add($col2)

        $sp = New-Object System.Windows.Controls.StackPanel
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Key
        $nameText.FontSize = 13
        $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
        $nameText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)
        $sp.Children.Add($nameText)

        $progressBorder = New-Object System.Windows.Controls.Border
        $progressBorder.Background = $window.FindResource("BorderBrush")
        $progressBorder.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $progressBorder.Height = 6

        $fillBorder = New-Object System.Windows.Controls.Border
        $fillBorder.CornerRadius = [System.Windows.CornerRadius]::new(3)
        $fillBorder.Height = 6
        $fillBorder.HorizontalAlignment = 'Left'
        $pct = [math]::Min(($app.Value / $maxUsage), 1)
        $fillBorder.Width = [math]::Max($pct * 250, 2)

        $colors = @("#6C63FF", "#00C853", "#FFB300", "#FF6584", "#03DAC5")
        $colorIndex = [array]::IndexOf(($sortedApps | ForEach-Object { $_.Key }), $app.Key) % $colors.Count
        $fillBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom($colors[$colorIndex])

        $progressBorder.Child = $fillBorder
        $sp.Children.Add($progressBorder)
        [System.Windows.Controls.Grid]::SetColumn($sp, 0)
        $grid.Children.Add($sp)

        $timeText = New-Object System.Windows.Controls.TextBlock
        $timeText.Text = Format-Duration $app.Value
        $timeText.FontSize = 13
        $timeText.Foreground = $window.FindResource("TextSecondaryBrush")
        $timeText.HorizontalAlignment = 'Right'
        $timeText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($timeText, 1)
        $grid.Children.Add($timeText)

        $appBorder.Child = $grid
        $DashTopApps.Children.Add($appBorder)
    }

    if ($sortedApps.Count -eq 0) {
        $noData = New-Object System.Windows.Controls.TextBlock
        $noData.Text = "No usage data yet - apps will appear as you use them"
        $noData.Foreground = $window.FindResource("TextSecondaryBrush")
        $noData.FontSize = 12
        $noData.FontStyle = 'Italic'
        $DashTopApps.Children.Add($noData)
    }

    # Usage Breakdown Chart
    Draw-UsageBreakdownChart

    # Category Breakdown
    Update-CategoryBreakdown

    # Running Apps
    Update-RunningApps
}

function Draw-UsageBreakdownChart {
    $DashChart.Children.Clear()
    $chartWidth = $DashChart.ActualWidth
    if ($chartWidth -lt 50) { $chartWidth = 320 }
    $chartHeight = 200

    $sortedApps = $script:CurrentAppUsage.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 6
    $totalUsage = ($sortedApps | Measure-Object -Property Value -Sum).Sum

    if (-not $totalUsage -or $totalUsage -eq 0) {
        $noData = New-Object System.Windows.Controls.TextBlock
        $noData.Text = "Collecting data..."
        $noData.Foreground = $window.FindResource("TextSecondaryBrush")
        $noData.FontSize = 12
        $noData.FontStyle = 'Italic'
        [System.Windows.Controls.Canvas]::SetLeft($noData, ($chartWidth / 2 - 50))
        [System.Windows.Controls.Canvas]::SetTop($noData, ($chartHeight / 2 - 10))
        $DashChart.Children.Add($noData)
        return
    }

    $colors = @("#6C63FF", "#FF6584", "#00C853", "#FFB300", "#03DAC5", "#BB86FC")
    $maxVal = ($sortedApps | Measure-Object -Property Value -Maximum).Maximum
    if (-not $maxVal -or $maxVal -eq 0) { $maxVal = 1 }

    $appCount = @($sortedApps).Count
    $totalBarSpace = $chartWidth - 20
    $gap = if ($appCount -gt 1) { 12 } else { 0 }
    $barWidth = [math]::Floor(($totalBarSpace - (($appCount - 1) * $gap)) / [math]::Max($appCount, 1))
    $barWidth = [math]::Min($barWidth, 60)
    $totalBarsWidth = ($barWidth * $appCount) + ($gap * [math]::Max($appCount - 1, 0))
    $startX = [math]::Max(($chartWidth - $totalBarsWidth) / 2, 10)

    $i = 0
    foreach ($app in $sortedApps) {
        $x = $startX + ($i * ($barWidth + $gap))
        $barHeight = [math]::Max(($app.Value / $maxVal) * ($chartHeight - 60), 4)
        $y = $chartHeight - 35 - $barHeight

        # Bar
        $bar = New-Object System.Windows.Shapes.Rectangle
        $bar.Width = $barWidth
        $bar.Height = $barHeight
        $bar.RadiusX = 4
        $bar.RadiusY = 4
        $bar.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($colors[$i % $colors.Count])
        [System.Windows.Controls.Canvas]::SetLeft($bar, $x)
        [System.Windows.Controls.Canvas]::SetTop($bar, $y)
        $DashChart.Children.Add($bar)

        # Time label above bar
        $valLabel = New-Object System.Windows.Controls.TextBlock
        $valLabel.Text = Format-Duration $app.Value
        $valLabel.FontSize = 9
        $valLabel.Foreground = $window.FindResource("TextPrimaryBrush")
        $valLabel.TextAlignment = 'Center'
        $valLabel.Width = $barWidth
        [System.Windows.Controls.Canvas]::SetLeft($valLabel, $x)
        [System.Windows.Controls.Canvas]::SetTop($valLabel, [math]::Max($y - 16, 0))
        $DashChart.Children.Add($valLabel)

        # App name label below bar
        $nameLabel = New-Object System.Windows.Controls.TextBlock
        $appDisplayName = $app.Key
        if ($appDisplayName.Length -gt 8) { $appDisplayName = $appDisplayName.Substring(0, 7) + ".." }
        $nameLabel.Text = $appDisplayName
        $nameLabel.FontSize = 9
        $nameLabel.Foreground = $window.FindResource("TextSecondaryBrush")
        $nameLabel.TextAlignment = 'Center'
        $nameLabel.Width = $barWidth
        [System.Windows.Controls.Canvas]::SetLeft($nameLabel, $x)
        [System.Windows.Controls.Canvas]::SetTop($nameLabel, $chartHeight - 30)
        $DashChart.Children.Add($nameLabel)

        # Percentage label
        $pctVal = [math]::Round(($app.Value / $totalUsage) * 100)
        $pctLabel = New-Object System.Windows.Controls.TextBlock
        $pctLabel.Text = "${pctVal}%"
        $pctLabel.FontSize = 8
        $pctLabel.Foreground = $window.FindResource("TextSecondaryBrush")
        $pctLabel.TextAlignment = 'Center'
        $pctLabel.Width = $barWidth
        [System.Windows.Controls.Canvas]::SetLeft($pctLabel, $x)
        [System.Windows.Controls.Canvas]::SetTop($pctLabel, $chartHeight - 16)
        $DashChart.Children.Add($pctLabel)

        $i++
    }
}

function Update-RunningApps {
    $DashRunningApps.Children.Clear()
    $apps = Get-RunningApps

    foreach ($app in ($apps | Select-Object -First 10)) {
        $border = New-Object System.Windows.Controls.Border
        $border.Background = $window.FindResource("BgSecondaryBrush")
        $border.BorderBrush = $window.FindResource("BorderBrush")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

        $grid = New-Object System.Windows.Controls.Grid
        $cols = @(40, 0, 150, 80) # 0 = star
        for ($i = 0; $i -lt $cols.Count; $i++) {
            $col = New-Object System.Windows.Controls.ColumnDefinition
            if ($cols[$i] -eq 0) {
                $col.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            } else {
                $col.Width = [System.Windows.GridLength]::new($cols[$i])
            }
            $grid.ColumnDefinitions.Add($col)
        }

        $iconText = New-Object System.Windows.Controls.TextBlock
        $iconText.Text = [string](Get-AppIcon $app.ProcessName)
        $iconText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
        $iconText.FontSize = 16
        $iconText.Foreground = $window.FindResource("PrimaryBrush")
        $iconText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($iconText, 0)
        $grid.Children.Add($iconText)

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.FontSize = 13
        $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
        $nameText.VerticalAlignment = 'Center'
        $nameText.TextTrimming = 'CharacterEllipsis'
        [System.Windows.Controls.Grid]::SetColumn($nameText, 1)
        $grid.Children.Add($nameText)

        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = if ($app.Title.Length -gt 25) { $app.Title.Substring(0, 25) + "..." } else { $app.Title }
        $titleText.FontSize = 11
        $titleText.Foreground = $window.FindResource("TextSecondaryBrush")
        $titleText.VerticalAlignment = 'Center'
        $titleText.TextTrimming = 'CharacterEllipsis'
        [System.Windows.Controls.Grid]::SetColumn($titleText, 2)
        $grid.Children.Add($titleText)

        $memText = New-Object System.Windows.Controls.TextBlock
        $memText.Text = "$($app.MemoryMB) MB"
        $memText.FontSize = 11
        $memText.Foreground = $window.FindResource("TextSecondaryBrush")
        $memText.HorizontalAlignment = 'Right'
        $memText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($memText, 3)
        $grid.Children.Add($memText)

        $border.Child = $grid
        $DashRunningApps.Children.Add($border)
    }

    if ($apps.Count -eq 0) {
        $noApps = New-Object System.Windows.Controls.TextBlock
        $noApps.Text = "No windowed applications detected"
        $noApps.Foreground = $window.FindResource("TextSecondaryBrush")
        $noApps.FontSize = 12
        $noApps.FontStyle = 'Italic'
        $DashRunningApps.Children.Add($noApps)
    }
}

function Update-CategoryBreakdown {
    $DashCategoryPanel.Children.Clear()

    if (-not $script:CurrentAppUsage -or $script:CurrentAppUsage.Count -eq 0) {
        $noData = New-Object System.Windows.Controls.TextBlock
        $noData.Text = "No usage data yet - categories will appear as you use apps"
        $noData.Foreground = $window.FindResource("TextSecondaryBrush")
        $noData.FontSize = 12
        $noData.FontStyle = 'Italic'
        $DashCategoryPanel.Children.Add($noData)
        return
    }

    # Aggregate usage by category
    $categoryUsage = @{}
    $categoryApps = @{}
    foreach ($entry in $script:CurrentAppUsage.GetEnumerator()) {
        $cat = Get-AppCategory $entry.Key
        if (-not $categoryUsage.ContainsKey($cat)) {
            $categoryUsage[$cat] = 0
            $categoryApps[$cat] = @()
        }
        $categoryUsage[$cat] += $entry.Value
        $categoryApps[$cat] += @(@{ Name = $entry.Key; Time = $entry.Value })
    }

    $sortedCats = $categoryUsage.GetEnumerator() | Sort-Object Value -Descending
    $maxUsage = ($sortedCats | Measure-Object -Property Value -Maximum).Maximum
    if (-not $maxUsage) { $maxUsage = 1 }
    $totalUsage = ($sortedCats | Measure-Object -Property Value -Sum).Sum
    if (-not $totalUsage) { $totalUsage = 1 }

    # Category grid layout
    $wrapPanel = New-Object System.Windows.Controls.WrapPanel
    $wrapPanel.Orientation = 'Horizontal'

    foreach ($cat in $sortedCats) {
        $catName = $cat.Key
        $catSeconds = $cat.Value
        $pct = [math]::Round(($catSeconds / $totalUsage) * 100)

        $catBorder = New-Object System.Windows.Controls.Border
        $catBorder.Background = $window.FindResource("BgSecondaryBrush")
        $catBorder.BorderBrush = $window.FindResource("BorderBrush")
        $catBorder.BorderThickness = [System.Windows.Thickness]::new(1)
        $catBorder.CornerRadius = [System.Windows.CornerRadius]::new(10)
        $catBorder.Padding = [System.Windows.Thickness]::new(16, 14, 16, 14)
        $catBorder.Margin = [System.Windows.Thickness]::new(0, 0, 10, 10)
        $catBorder.Width = 280

        $sp = New-Object System.Windows.Controls.StackPanel

        # Header row: icon + category name + percentage
        $headerGrid = New-Object System.Windows.Controls.Grid
        $hCol1 = New-Object System.Windows.Controls.ColumnDefinition
        $hCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $hCol2 = New-Object System.Windows.Controls.ColumnDefinition
        $hCol2.Width = [System.Windows.GridLength]::new(60)
        $headerGrid.ColumnDefinitions.Add($hCol1)
        $headerGrid.ColumnDefinitions.Add($hCol2)

        $headerSp = New-Object System.Windows.Controls.StackPanel
        $headerSp.Orientation = 'Horizontal'

        $catIcon = New-Object System.Windows.Controls.TextBlock
        $iconChar = if ($script:CategoryIcons.ContainsKey($catName)) { $script:CategoryIcons[$catName] } else { [char]0xE71D }
        $catIcon.Text = [string]$iconChar
        $catIcon.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
        $catIcon.FontSize = 18
        $catColor = if ($script:CategoryColors.ContainsKey($catName)) { $script:CategoryColors[$catName] } else { "#8892B0" }
        $catIcon.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($catColor)
        $catIcon.VerticalAlignment = 'Center'
        $catIcon.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
        $headerSp.Children.Add($catIcon)

        $catTitle = New-Object System.Windows.Controls.TextBlock
        $catTitle.Text = $catName
        $catTitle.FontSize = 14
        $catTitle.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Semibold")
        $catTitle.Foreground = $window.FindResource("TextPrimaryBrush")
        $catTitle.VerticalAlignment = 'Center'
        $headerSp.Children.Add($catTitle)

        [System.Windows.Controls.Grid]::SetColumn($headerSp, 0)
        $headerGrid.Children.Add($headerSp)

        $pctText = New-Object System.Windows.Controls.TextBlock
        $pctText.Text = "${pct}%"
        $pctText.FontSize = 14
        $pctText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Semibold")
        $pctText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFrom($catColor)
        $pctText.HorizontalAlignment = 'Right'
        $pctText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($pctText, 1)
        $headerGrid.Children.Add($pctText)

        $sp.Children.Add($headerGrid)

        # Time text
        $timeText = New-Object System.Windows.Controls.TextBlock
        $timeText.Text = Format-Duration $catSeconds
        $timeText.FontSize = 12
        $timeText.Foreground = $window.FindResource("TextSecondaryBrush")
        $timeText.Margin = [System.Windows.Thickness]::new(28, 2, 0, 6)
        $sp.Children.Add($timeText)

        # Progress bar
        $progressBg = New-Object System.Windows.Controls.Border
        $progressBg.Background = $window.FindResource("BorderBrush")
        $progressBg.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $progressBg.Height = 6
        $progressBg.Margin = [System.Windows.Thickness]::new(0, 0, 0, 8)

        $progressFill = New-Object System.Windows.Controls.Border
        $progressFill.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $progressFill.Height = 6
        $progressFill.HorizontalAlignment = 'Left'
        $barPct = [math]::Min(($catSeconds / $maxUsage), 1)
        $progressFill.Width = [math]::Max($barPct * 248, 2)
        $progressFill.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom($catColor)
        $progressBg.Child = $progressFill
        $sp.Children.Add($progressBg)

        # Top apps in this category
        $topApps = $categoryApps[$catName] | Sort-Object { $_.Time } -Descending | Select-Object -First 3
        foreach ($topApp in $topApps) {
            $appRow = New-Object System.Windows.Controls.Grid
            $aCol1 = New-Object System.Windows.Controls.ColumnDefinition
            $aCol1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $aCol2 = New-Object System.Windows.Controls.ColumnDefinition
            $aCol2.Width = [System.Windows.GridLength]::new(70)
            $appRow.ColumnDefinitions.Add($aCol1)
            $appRow.ColumnDefinitions.Add($aCol2)

            $appNameTb = New-Object System.Windows.Controls.TextBlock
            $appNameTb.Text = $topApp.Name
            $appNameTb.FontSize = 11
            $appNameTb.Foreground = $window.FindResource("TextSecondaryBrush")
            $appNameTb.TextTrimming = 'CharacterEllipsis'
            $appNameTb.Margin = [System.Windows.Thickness]::new(28, 0, 0, 2)
            [System.Windows.Controls.Grid]::SetColumn($appNameTb, 0)
            $appRow.Children.Add($appNameTb)

            $appTimeTb = New-Object System.Windows.Controls.TextBlock
            $appTimeTb.Text = Format-Duration $topApp.Time
            $appTimeTb.FontSize = 11
            $appTimeTb.Foreground = $window.FindResource("TextSecondaryBrush")
            $appTimeTb.HorizontalAlignment = 'Right'
            [System.Windows.Controls.Grid]::SetColumn($appTimeTb, 1)
            $appRow.Children.Add($appTimeTb)

            $sp.Children.Add($appRow)
        }

        $catBorder.Child = $sp
        $wrapPanel.Children.Add($catBorder)
    }

    $DashCategoryPanel.Children.Add($wrapPanel)
}

# ── App Usage Page ──
$script:SystemApps = @("explorer", "SearchHost", "ShellExperienceHost", "StartMenuExperienceHost",
                        "TextInputHost", "SecurityHealthSystray", "SystemSettings", "LockApp",
                        "RuntimeBroker", "dwm", "csrss", "svchost", "conhost", "Taskmgr",
                        "ApplicationFrameHost", "WidgetService", "CompPkgSrv", "dllhost",
                        "sihost", "fontdrvhost", "ctfmon", "taskhostw", "smartscreen")

function Update-AppsList {
    $AppsListPanel.Children.Clear()
    $ThirdPartyAppsPanel.Children.Clear()

    $apps = Get-RunningApps
    $searchText = $AppSearchBox.Text

    if ($searchText) {
        $apps = $apps | Where-Object { $_.Name -like "*$searchText*" -or $_.Title -like "*$searchText*" }
    }

    $thirdPartyApps = @()
    $systemAppsList = @()

    foreach ($app in $apps) {
        if ($app.ProcessName -in $script:SystemApps) {
            $systemAppsList += $app
        } else {
            $thirdPartyApps += $app
        }
    }

    # All apps list
    foreach ($app in $apps) {
        $border = New-Object System.Windows.Controls.Border
        $border.Padding = [System.Windows.Thickness]::new(16, 10, 16, 10)
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 1)
        $border.BorderBrush = $window.FindResource("BorderBrush")
        $border.BorderThickness = [System.Windows.Thickness]::new(0, 0, 0, 1)

        $grid = New-Object System.Windows.Controls.Grid
        $widths = @(40, 0, 150, 100, 100, 80)
        for ($i = 0; $i -lt $widths.Count; $i++) {
            $col = New-Object System.Windows.Controls.ColumnDefinition
            if ($widths[$i] -eq 0) {
                $col.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            } else {
                $col.Width = [System.Windows.GridLength]::new($widths[$i])
            }
            $grid.ColumnDefinitions.Add($col)
        }

        # Icon
        $iconText = New-Object System.Windows.Controls.TextBlock
        $iconText.Text = [string](Get-AppIcon $app.ProcessName)
        $iconText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
        $iconText.FontSize = 16
        $iconText.Foreground = $window.FindResource("PrimaryBrush")
        $iconText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($iconText, 0)
        $grid.Children.Add($iconText)

        # Name
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.FontSize = 13
        $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
        $nameText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($nameText, 1)
        $grid.Children.Add($nameText)

        # Title
        $titleText = New-Object System.Windows.Controls.TextBlock
        $titleText.Text = if ($app.Title.Length -gt 20) { $app.Title.Substring(0, 20) + "..." } else { $app.Title }
        $titleText.FontSize = 11
        $titleText.Foreground = $window.FindResource("TextSecondaryBrush")
        $titleText.VerticalAlignment = 'Center'
        $titleText.TextTrimming = 'CharacterEllipsis'
        [System.Windows.Controls.Grid]::SetColumn($titleText, 2)
        $grid.Children.Add($titleText)

        # Usage Time
        $usageTime = 0
        if ($script:CurrentAppUsage.ContainsKey($app.Name)) {
            $usageTime = $script:CurrentAppUsage[$app.Name]
        }
        $timeText = New-Object System.Windows.Controls.TextBlock
        $timeText.Text = Format-Duration $usageTime
        $timeText.FontSize = 12
        $timeText.Foreground = $window.FindResource("TextPrimaryBrush")
        $timeText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($timeText, 3)
        $grid.Children.Add($timeText)

        # Memory
        $memText = New-Object System.Windows.Controls.TextBlock
        $memText.Text = "$($app.MemoryMB) MB"
        $memText.FontSize = 12
        $memText.Foreground = $window.FindResource("TextSecondaryBrush")
        $memText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($memText, 4)
        $grid.Children.Add($memText)

        # Status
        $statusBorder = New-Object System.Windows.Controls.Border
        $statusBgColor = if ($script:CurrentTheme) { $script:CurrentTheme['StatusBg'] } else { '#1B3A2A' }
        $statusBorder.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom($statusBgColor)
        $statusBorder.CornerRadius = [System.Windows.CornerRadius]::new(4)
        $statusBorder.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $statusBorder.HorizontalAlignment = 'Center'
        $statusBorder.VerticalAlignment = 'Center'
        $statusText = New-Object System.Windows.Controls.TextBlock
        $statusText.Text = "Running"
        $statusText.FontSize = 10
        $statusText.Foreground = $window.FindResource("SuccessBrush")
        $statusBorder.Child = $statusText
        [System.Windows.Controls.Grid]::SetColumn($statusBorder, 5)
        $grid.Children.Add($statusBorder)

        $border.Child = $grid
        $AppsListPanel.Children.Add($border)
    }

    # Third-party apps
    foreach ($app in $thirdPartyApps) {
        $border = New-Object System.Windows.Controls.Border
        $border.Background = $window.FindResource("BgSecondaryBrush")
        $border.BorderBrush = $window.FindResource("BorderBrush")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $border.Padding = [System.Windows.Thickness]::new(16, 10, 16, 10)
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'

        $iconText = New-Object System.Windows.Controls.TextBlock
        $iconText.Text = [string](Get-AppIcon $app.ProcessName)
        $iconText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
        $iconText.FontSize = 18
        $iconText.Foreground = $window.FindResource("AccentBrush")
        $iconText.VerticalAlignment = 'Center'
        $iconText.Margin = [System.Windows.Thickness]::new(0, 0, 12, 0)
        $sp.Children.Add($iconText)

        $infoSp = New-Object System.Windows.Controls.StackPanel
        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $app.Name
        $nameText.FontSize = 14
        $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
        $infoSp.Children.Add($nameText)

        $detailText = New-Object System.Windows.Controls.TextBlock
        $usageTime = 0
        if ($script:CurrentAppUsage.ContainsKey($app.Name)) {
            $usageTime = $script:CurrentAppUsage[$app.Name]
        }
        $detailText.Text = "$($app.Title) | $(Format-Duration $usageTime) | $($app.MemoryMB) MB"
        $detailText.FontSize = 11
        $detailText.Foreground = $window.FindResource("TextSecondaryBrush")
        $infoSp.Children.Add($detailText)

        $sp.Children.Add($infoSp)
        $border.Child = $sp
        $ThirdPartyAppsPanel.Children.Add($border)
    }

    if ($thirdPartyApps.Count -eq 0) {
        $noApps = New-Object System.Windows.Controls.TextBlock
        $noApps.Text = "No third-party applications detected"
        $noApps.Foreground = $window.FindResource("TextSecondaryBrush")
        $noApps.FontSize = 12
        $noApps.FontStyle = 'Italic'
        $ThirdPartyAppsPanel.Children.Add($noApps)
    }
}

$RefreshAppsBtn.Add_Click({ Update-AppsList })
$AppSearchBox.Add_TextChanged({ Update-AppsList })

# ── Screen Time Page ──
function Update-ScreenTime {
    $totalSec = $script:TotalScreenTimeToday
    $hours = [math]::Floor($totalSec / 3600)
    $mins = [math]::Floor(($totalSec % 3600) / 60)
    $STTotalTime.Text = "${hours}h ${mins}m"

    $sessionSec = ((Get-Date) - $script:SessionStart).TotalSeconds
    $sHours = [math]::Floor($sessionSec / 3600)
    $sMins = [math]::Floor(($sessionSec % 3600) / 60)
    $STSessionTime.Text = "${sHours}h ${sMins}m"

    $STAppsUsed.Text = $script:CurrentAppUsage.Count.ToString()

    # Weekly chart
    Draw-WeeklyChart

    # Hourly chart
    Draw-HourlyChart
}

function Draw-WeeklyChart {
    $WeeklyChart.Children.Clear()
    $chartWidth = 600
    $chartHeight = 200
    $barWidth = 60
    $gap = 20
    $days = @("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
    $today = (Get-Date).DayOfWeek.value__
    if ($today -eq 0) { $today = 7 }

    $weekData = @()
    for ($i = 6; $i -ge 0; $i--) {
        $date = (Get-Date).AddDays(-$i)
        $key = $date.ToString("yyyy-MM-dd")
        $dayTotal = 0
        if ($script:UsageData.$key) {
            $dayData = $script:UsageData.$key
            if ($dayData -is [PSCustomObject]) {
                foreach ($prop in $dayData.PSObject.Properties) {
                    $dayTotal += $prop.Value
                }
            }
        }
        if ($key -eq $script:TodayKey) { $dayTotal = $script:TotalScreenTimeToday }
        $weekData += $dayTotal
    }

    $maxVal = ($weekData | Measure-Object -Maximum).Maximum
    if (-not $maxVal -or $maxVal -eq 0) { $maxVal = 3600 }

    for ($i = 0; $i -lt 7; $i++) {
        $x = 40 + ($i * ($barWidth + $gap))
        $barHeight = [math]::Max(($weekData[$i] / $maxVal) * ($chartHeight - 40), 2)
        $y = $chartHeight - 30 - $barHeight

        $bar = New-Object System.Windows.Shapes.Rectangle
        $bar.Width = $barWidth
        $bar.Height = $barHeight
        $bar.RadiusX = 6
        $bar.RadiusY = 6

        if ($i -eq 6) {
            $bar.Fill = $window.FindResource("PrimaryBrush")
        } else {
            $chartBgColor = if ($script:CurrentTheme) { $script:CurrentTheme['ChartBarBg'] } else { '#2D3A5C' }
            $bar.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($chartBgColor)
        }

        [System.Windows.Controls.Canvas]::SetLeft($bar, $x)
        [System.Windows.Controls.Canvas]::SetTop($bar, $y)
        $WeeklyChart.Children.Add($bar)

        # Day label
        $dayLabel = New-Object System.Windows.Controls.TextBlock
        $dayLabel.Text = $days[(((Get-Date).AddDays(-6 + $i)).DayOfWeek.value__ + 6) % 7]
        $dayLabel.FontSize = 10
        $dayLabel.Foreground = $window.FindResource("TextSecondaryBrush")
        $dayLabel.TextAlignment = 'Center'
        $dayLabel.Width = $barWidth
        [System.Windows.Controls.Canvas]::SetLeft($dayLabel, $x)
        [System.Windows.Controls.Canvas]::SetTop($dayLabel, $chartHeight - 20)
        $WeeklyChart.Children.Add($dayLabel)

        # Value label
        $valLabel = New-Object System.Windows.Controls.TextBlock
        $valHours = [math]::Round($weekData[$i] / 3600, 1)
        $valLabel.Text = "${valHours}h"
        $valLabel.FontSize = 10
        $valLabel.Foreground = $window.FindResource("TextPrimaryBrush")
        $valLabel.TextAlignment = 'Center'
        $valLabel.Width = $barWidth
        [System.Windows.Controls.Canvas]::SetLeft($valLabel, $x)
        [System.Windows.Controls.Canvas]::SetTop($valLabel, [math]::Max($y - 18, 0))
        $WeeklyChart.Children.Add($valLabel)
    }
}

function Draw-HourlyChart {
    $HourlyChart.Children.Clear()
    $chartWidth = 600
    $chartHeight = 140
    $barWidth = 20
    $gap = 4

    $hourData = @(0) * 24
    $currentHour = (Get-Date).Hour
    $hourData[$currentHour] = [math]::Max($script:TotalScreenTimeToday / 24, 60)

    foreach ($app in $script:CurrentAppUsage.GetEnumerator()) {
        $hourData[$currentHour] += $app.Value / 24
    }

    $maxVal = ($hourData | Measure-Object -Maximum).Maximum
    if (-not $maxVal -or $maxVal -eq 0) { $maxVal = 3600 }

    for ($h = 0; $h -lt 24; $h++) {
        $x = 10 + ($h * ($barWidth + $gap))
        $barHeight = [math]::Max(($hourData[$h] / $maxVal) * ($chartHeight - 30), 1)
        $y = $chartHeight - 25 - $barHeight

        $bar = New-Object System.Windows.Shapes.Rectangle
        $bar.Width = $barWidth
        $bar.Height = $barHeight
        $bar.RadiusX = 3
        $bar.RadiusY = 3

        if ($h -eq $currentHour) {
            $bar.Fill = $window.FindResource("AccentBrush")
        } elseif ($h -lt $currentHour) {
            $bar.Fill = $window.FindResource("PrimaryBrush")
            $bar.Opacity = 0.5
        } else {
            $chartBgColor2 = if ($script:CurrentTheme) { $script:CurrentTheme['ChartBarBg'] } else { '#2D3A5C' }
            $bar.Fill = [System.Windows.Media.BrushConverter]::new().ConvertFrom($chartBgColor2)
        }

        [System.Windows.Controls.Canvas]::SetLeft($bar, $x)
        [System.Windows.Controls.Canvas]::SetTop($bar, $y)
        $HourlyChart.Children.Add($bar)

        # Hour label (every 3 hours)
        if ($h % 3 -eq 0) {
            $label = New-Object System.Windows.Controls.TextBlock
            $label.Text = "${h}:00"
            $label.FontSize = 9
            $label.Foreground = $window.FindResource("TextSecondaryBrush")
            [System.Windows.Controls.Canvas]::SetLeft($label, $x - 5)
            [System.Windows.Controls.Canvas]::SetTop($label, $chartHeight - 18)
            $HourlyChart.Children.Add($label)
        }
    }
}

# ── Theme System ──
function Get-WindowsTheme {
    try {
        $regPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        $val = Get-ItemProperty -Path $regPath -Name "AppsUseLightTheme" -ErrorAction SilentlyContinue
        if ($null -ne $val -and $val.AppsUseLightTheme -eq 0) { return "Dark" }
        return "Light"
    } catch { return "Dark" }
}

function Apply-Theme {
    param([string]$ThemeName)

    $script:DarkTheme = @{
        BgColor          = "#1A1A2E"; BgSecondaryColor = "#16213E"
        CardColor        = "#1F2940"; CardHoverColor   = "#263250"
        TextPrimaryColor = "#FFFFFF"; TextSecondaryColor = "#8892B0"
        BorderColor      = "#2D3A5C"
        StatIcon1Bg      = "#2D1F6B"; StatIcon2Bg = "#1B3A2A"
        StatIcon3Bg      = "#3A2A1B"; StatIcon4Bg = "#3A1B2A"
        ChartBarBg       = "#2D3A5C"; StatusBg = "#1B3A2A"
        CaretBrush       = "White"
        ToggleTrack      = "#3D4663"
        ScrollBarBg      = "#2D3A5C"
        SeparatorColor   = "#2D3A5C"
    }
    $script:LightTheme = @{
        BgColor          = "#F0F2F5"; BgSecondaryColor = "#FFFFFF"
        CardColor        = "#FFFFFF"; CardHoverColor   = "#E8EAF0"
        TextPrimaryColor = "#1A1A2E"; TextSecondaryColor = "#5A6078"
        BorderColor      = "#D0D4DC"
        StatIcon1Bg      = "#E8E5FF"; StatIcon2Bg = "#E5F5EC"
        StatIcon3Bg      = "#FFF3E0"; StatIcon4Bg = "#FDE5EC"
        ChartBarBg       = "#D0D4DC"; StatusBg = "#E5F5EC"
        CaretBrush       = "Black"
        ToggleTrack      = "#C4C7D0"
        ScrollBarBg      = "#D0D4DC"
        SeparatorColor   = "#D0D4DC"
    }

    $resolved = $ThemeName
    if ($ThemeName -eq "Windows Default") {
        $resolved = Get-WindowsTheme
    }
    $script:IsLightTheme = ($resolved -eq "Light")

    $colors = if ($script:IsLightTheme) { $script:LightTheme } else { $script:DarkTheme }
    $script:CurrentTheme = $colors
    $converter = [System.Windows.Media.BrushConverter]::new()

    # Update Color resources and modify existing Brush resources in-place
    $script:ThemeBrushes = @{}
    $themeKeys = @('BgColor','BgSecondaryColor','CardColor','CardHoverColor','TextPrimaryColor','TextSecondaryColor','BorderColor')
    foreach ($key in $themeKeys) {
        $brushKey = $key -replace 'Color$', 'Brush'
        $newColor = [System.Windows.Media.ColorConverter]::ConvertFromString($colors[$key])
        $window.Resources[$key] = $newColor
        # Try to modify existing brush Color in-place (updates StaticResource references)
        $existingBrush = $window.Resources[$brushKey]
        if ($existingBrush -is [System.Windows.Media.SolidColorBrush]) {
            try {
                $existingBrush.Color = $newColor
                $script:ThemeBrushes[$brushKey] = $existingBrush
            } catch {
                $newBrush = New-Object System.Windows.Media.SolidColorBrush($newColor)
                $window.Resources[$brushKey] = $newBrush
                $script:ThemeBrushes[$brushKey] = $newBrush
            }
        } else {
            $newBrush = New-Object System.Windows.Media.SolidColorBrush($newColor)
            $window.Resources[$brushKey] = $newBrush
            $script:ThemeBrushes[$brushKey] = $newBrush
        }
    }

    # Known dark and light foreground hex values
    $script:AllPrimaryFgHexes = @('#FFFFFFFF', '#FF1A1A2E', '#FF000000')
    $script:AllSecondaryFgHexes = @('#FF8892B0', '#FF5A6078', '#FF808080')
    # Known dark and light background hex values
    $script:AllCardBgHexes = @('#FF1F2940', '#FFFFFFFF')
    $script:AllBgSecondaryHexes = @('#FF16213E', '#FFF0F2F5', '#FFFFFFFF')
    $script:AllBorderHexes = @('#FF2D3A5C', '#FFD0D4DC')
    $script:AllToggleTrackHexes = @('#FF3D4663', '#FFC4C7D0')
    $script:AllBgHexes = @('#FF1A1A2E', '#FFF0F2F5')

    # ─── Direct element updates ───

    # Main window border
    $mainBorder = $window.Content
    if ($mainBorder -is [System.Windows.Controls.Border]) {
        $mainBorder.Background = $converter.ConvertFrom($colors['BgColor'])
        $mainBorder.BorderBrush = $converter.ConvertFrom($colors['BorderColor'])
    }

    # Title bar
    try {
        $TitleBar.Background = $converter.ConvertFrom($colors['BgSecondaryColor'])
    } catch { }

    # Sidebar
    try {
        $sidebarBorder = $mainBorder.Child.Children[1].Children[0]
        if ($sidebarBorder -is [System.Windows.Controls.Border]) {
            $sidebarBorder.Background = $converter.ConvertFrom($colors['BgSecondaryColor'])
        }
    } catch { }

    # Title bar buttons (minimize, maximize, close)
    try {
        $MinBtn.Foreground = $converter.ConvertFrom($colors['TextSecondaryColor'])
        $MaxBtn.Foreground = $converter.ConvertFrom($colors['TextSecondaryColor'])
        $CloseBtn.Foreground = $converter.ConvertFrom($colors['TextSecondaryColor'])
    } catch { }

    # Stat icon backgrounds
    try {
        $StatIcon1Bg.Background = $converter.ConvertFrom($colors['StatIcon1Bg'])
        $StatIcon2Bg.Background = $converter.ConvertFrom($colors['StatIcon2Bg'])
        $StatIcon3Bg.Background = $converter.ConvertFrom($colors['StatIcon3Bg'])
        $StatIcon4Bg.Background = $converter.ConvertFrom($colors['StatIcon4Bg'])
    } catch { }

    # Sidebar text elements
    try {
        $UserNameText.Foreground = $converter.ConvertFrom($colors['TextPrimaryColor'])
        $ScreenTimeLabel.Foreground = $converter.ConvertFrom($colors['TextSecondaryColor'])
    } catch { }

    # Nav button foreground colors (icons + text) - walk into visual tree
    $navSecondaryBrush = $converter.ConvertFrom($colors['TextSecondaryColor'])
    foreach ($btn in $script:NavButtons) {
        try {
            $btn.Foreground = $navSecondaryBrush
            function Set-BtnChildFg {
                param($el, $brush)
                if ($el -is [System.Windows.Controls.TextBlock]) {
                    $el.Foreground = $brush
                }
                $cnt = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
                for ($k = 0; $k -lt $cnt; $k++) {
                    $ch = [System.Windows.Media.VisualTreeHelper]::GetChild($el, $k)
                    Set-BtnChildFg $ch $brush
                }
            }
            Set-BtnChildFg $btn $navSecondaryBrush
        } catch { }
    }

    # Also update sidebar section labels ("MENU", "SYSTEM") by walking the sidebar
    try {
        $sidebar = $mainBorder.Child.Children[1].Children[0]
        function Update-SidebarTexts {
            param($el)
            if ($el -is [System.Windows.Controls.TextBlock]) {
                $fg = $el.Foreground
                if ($fg -is [System.Windows.Media.SolidColorBrush]) {
                    $hex = $fg.Color.ToString()
                    if ($script:AllPrimaryFgHexes -contains $hex) {
                        $el.Foreground = $converter.ConvertFrom($colors['TextPrimaryColor'])
                    }
                    elseif ($script:AllSecondaryFgHexes -contains $hex) {
                        $el.Foreground = $converter.ConvertFrom($colors['TextSecondaryColor'])
                    }
                }
            }
            $count = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($el)
            for ($j = 0; $j -lt $count; $j++) {
                $child = [System.Windows.Media.VisualTreeHelper]::GetChild($el, $j)
                Update-SidebarTexts $child
            }
        }
        Update-SidebarTexts $sidebar
    } catch { }

    # ─── Visual tree walker ───
    function Update-ElementColors {
        param($element)
        if (-not $element) { return }

        $textPrimaryBrush = $converter.ConvertFrom($colors['TextPrimaryColor'])
        $textSecondaryBrush = $converter.ConvertFrom($colors['TextSecondaryColor'])
        $cardBrush = $converter.ConvertFrom($colors['CardColor'])
        $bgSecBrush = $converter.ConvertFrom($colors['BgSecondaryColor'])
        $borderBrush = $converter.ConvertFrom($colors['BorderColor'])
        $toggleBrush = $converter.ConvertFrom($colors['ToggleTrack'])

        # TextBlock foreground
        if ($element -is [System.Windows.Controls.TextBlock]) {
            $fg = $element.Foreground
            if ($fg -is [System.Windows.Media.SolidColorBrush]) {
                $hex = $fg.Color.ToString()
                if ($script:AllPrimaryFgHexes -contains $hex) {
                    $element.Foreground = $textPrimaryBrush
                }
                elseif ($script:AllSecondaryFgHexes -contains $hex) {
                    $element.Foreground = $textSecondaryBrush
                }
            }
        }

        # Control foreground (buttons, labels, etc. — not textboxes)
        if ($element -is [System.Windows.Controls.Control] -and
            $element -isnot [System.Windows.Controls.TextBox] -and
            $element -isnot [System.Windows.Controls.PasswordBox] -and
            $element -isnot [System.Windows.Controls.ComboBox]) {
            try {
                $fg = $element.Foreground
                if ($fg -is [System.Windows.Media.SolidColorBrush]) {
                    $hex = $fg.Color.ToString()
                    if ($script:AllPrimaryFgHexes -contains $hex) {
                        $element.Foreground = $textPrimaryBrush
                    }
                    elseif ($script:AllSecondaryFgHexes -contains $hex) {
                        $element.Foreground = $textSecondaryBrush
                    }
                }
            } catch { }
        }

        # Border backgrounds and border brushes
        if ($element -is [System.Windows.Controls.Border]) {
            $bg = $element.Background
            if ($bg -is [System.Windows.Media.SolidColorBrush]) {
                $hex = $bg.Color.ToString()
                if ($script:AllCardBgHexes -contains $hex) {
                    $element.Background = $cardBrush
                }
                elseif ($script:AllBgHexes -contains $hex) {
                    $element.Background = $converter.ConvertFrom($colors['BgColor'])
                }
                elseif ($script:AllToggleTrackHexes -contains $hex) {
                    $element.Background = $toggleBrush
                }
            }
            $bb = $element.BorderBrush
            if ($bb -is [System.Windows.Media.SolidColorBrush]) {
                $hex = $bb.Color.ToString()
                if ($script:AllBorderHexes -contains $hex) {
                    $element.BorderBrush = $borderBrush
                }
            }
        }

        # TextBox / PasswordBox
        if ($element -is [System.Windows.Controls.TextBox] -or $element -is [System.Windows.Controls.PasswordBox]) {
            try {
                $element.Background = $bgSecBrush
                $element.Foreground = $textPrimaryBrush
                $element.BorderBrush = $borderBrush
                $element.CaretBrush = $converter.ConvertFrom($colors['CaretBrush'])
            } catch { }
        }

        # ComboBox
        if ($element -is [System.Windows.Controls.ComboBox]) {
            try {
                $element.Background = $bgSecBrush
                $element.Foreground = $textPrimaryBrush
                $element.BorderBrush = $borderBrush
            } catch { }
        }

        # Recurse into visual children
        $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($element)
        for ($i = 0; $i -lt $childCount; $i++) {
            $child = [System.Windows.Media.VisualTreeHelper]::GetChild($element, $i)
            Update-ElementColors $child
        }
    }

    # Walk entire visual tree
    Update-ElementColors $window

    # Refresh the current page to regenerate dynamic content with correct colors
    $currentPageIndex = -1
    for ($i = 0; $i -lt $script:Pages.Count; $i++) {
        if ($script:Pages[$i].Visibility -eq 'Visible') { $currentPageIndex = $i; break }
    }
    if ($currentPageIndex -ge 0) {
        Switch-Page $currentPageIndex
    }

    $script:Config.Theme = $ThemeName
    Save-JsonData -Path $ConfigFile -Data $script:Config
}

# ── Running Apps List for Time Limits ──
function Update-LimitsAppList {
    $LimitsAppListPanel.Children.Clear()

    $apps = @()
    if ($script:CurrentAppUsage -and $script:CurrentAppUsage.Count -gt 0) {
        $apps = $script:CurrentAppUsage.GetEnumerator() | Sort-Object Value -Descending
    }

    if ($apps.Count -eq 0) {
        $emptyText = New-Object System.Windows.Controls.TextBlock
        $emptyText.Text = "No tracked apps yet. Usage data will appear as you use applications."
        $emptyText.Foreground = $window.FindResource("TextSecondaryBrush")
        $emptyText.FontSize = 12
        $emptyText.FontStyle = 'Italic'
        $LimitsAppListPanel.Children.Add($emptyText)
        return
    }

    foreach ($app in $apps) {
        $appName = $app.Key
        $usageSec = $app.Value
        $usageMin = [math]::Floor($usageSec / 60)
        $usageStr = if ($usageMin -ge 60) { "{0}h {1}m" -f [math]::Floor($usageMin / 60), ($usageMin % 60) } else { "${usageMin}m" }

        $border = New-Object System.Windows.Controls.Border
        $border.Background = $window.FindResource("BgSecondaryBrush")
        $border.BorderBrush = $window.FindResource("BorderBrush")
        $border.BorderThickness = [System.Windows.Thickness]::new(1)
        $border.CornerRadius = [System.Windows.CornerRadius]::new(6)
        $border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

        $grid = New-Object System.Windows.Controls.Grid
        $c1 = New-Object System.Windows.Controls.ColumnDefinition
        $c1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
        $c2 = New-Object System.Windows.Controls.ColumnDefinition
        $c2.Width = [System.Windows.GridLength]::new(80)
        $c3 = New-Object System.Windows.Controls.ColumnDefinition
        $c3.Width = [System.Windows.GridLength]::new(100)
        $grid.ColumnDefinitions.Add($c1)
        $grid.ColumnDefinitions.Add($c2)
        $grid.ColumnDefinitions.Add($c3)

        $nameText = New-Object System.Windows.Controls.TextBlock
        $nameText.Text = $appName
        $nameText.FontSize = 12
        $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
        $nameText.VerticalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($nameText, 0)

        $usageText = New-Object System.Windows.Controls.TextBlock
        $usageText.Text = $usageStr
        $usageText.FontSize = 11
        $usageText.Foreground = $window.FindResource("TextSecondaryBrush")
        $usageText.VerticalAlignment = 'Center'
        $usageText.HorizontalAlignment = 'Center'
        [System.Windows.Controls.Grid]::SetColumn($usageText, 1)

        $setBtn = New-Object System.Windows.Controls.Button
        $setBtn.Content = "Set Limit"
        $setBtn.Style = $window.FindResource("ModernButton")
        $setBtn.FontSize = 11
        $setBtn.Padding = [System.Windows.Thickness]::new(8, 2, 8, 2)
        $setBtn.Tag = $appName
        [System.Windows.Controls.Grid]::SetColumn($setBtn, 2)

        $setBtn.Add_Click({
            param($sender, $e)
            $clickedApp = $sender.Tag
            $LimitAppName.Text = $clickedApp
            $LimitMinutes.Focus()
        })

        $grid.Children.Add($nameText)
        $grid.Children.Add($usageText)
        $grid.Children.Add($setBtn)
        $border.Child = $grid
        $LimitsAppListPanel.Children.Add($border)
    }
}

# ── Time Limits Page ──
function Update-LimitsList {
    $LimitsListPanel.Children.Clear()
    $hasLimits = $false

    if ($script:Limits -is [PSCustomObject] -and $script:Limits.PSObject.Properties.Count -gt 0) {
        foreach ($prop in $script:Limits.PSObject.Properties) {
            $hasLimits = $true
            $appName = $prop.Name
            $limitMin = $prop.Value

            $border = New-Object System.Windows.Controls.Border
            $border.Background = $window.FindResource("BgSecondaryBrush")
            $border.BorderBrush = $window.FindResource("BorderBrush")
            $border.BorderThickness = [System.Windows.Thickness]::new(1)
            $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $border.Padding = [System.Windows.Thickness]::new(16, 12, 16, 12)
            $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

            $grid = New-Object System.Windows.Controls.Grid
            $col1 = New-Object System.Windows.Controls.ColumnDefinition
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = New-Object System.Windows.Controls.ColumnDefinition
            $col2.Width = [System.Windows.GridLength]::new(120)
            $col3 = New-Object System.Windows.Controls.ColumnDefinition
            $col3.Width = [System.Windows.GridLength]::new(100)
            $col4 = New-Object System.Windows.Controls.ColumnDefinition
            $col4.Width = [System.Windows.GridLength]::new(90)
            $grid.ColumnDefinitions.Add($col1)
            $grid.ColumnDefinitions.Add($col2)
            $grid.ColumnDefinitions.Add($col3)
            $grid.ColumnDefinitions.Add($col4)

            # App name
            $sp = New-Object System.Windows.Controls.StackPanel
            $nameText = New-Object System.Windows.Controls.TextBlock
            $nameText.Text = $appName
            $nameText.FontSize = 14
            $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
            $sp.Children.Add($nameText)

            $usedSec = 0
            if ($script:CurrentAppUsage.ContainsKey($appName)) {
                $usedSec = $script:CurrentAppUsage[$appName]
            }
            $usedMin = [math]::Floor($usedSec / 60)
            $pctUsed = if ($limitMin -gt 0) { [math]::Min([math]::Round(($usedMin / $limitMin) * 100), 100) } else { 0 }

            $isBlocked = $script:BlockedByLimit.Values -contains $appName
            $detailText = New-Object System.Windows.Controls.TextBlock
            if ($isBlocked) {
                $detailText.Text = "BLOCKED - $usedMin / $limitMin min"
                $detailText.Foreground = $window.FindResource("DangerBrush")
            } else {
                $detailText.Text = "$usedMin / $limitMin min ($pctUsed%)"
                $detailText.Foreground = $window.FindResource("TextSecondaryBrush")
            }
            $detailText.FontSize = 11
            $sp.Children.Add($detailText)
            [System.Windows.Controls.Grid]::SetColumn($sp, 0)
            $grid.Children.Add($sp)

            # Progress bar
            $progressBg = New-Object System.Windows.Controls.Border
            $progressBgColor = if ($script:CurrentTheme) { $script:CurrentTheme['ChartBarBg'] } else { '#2D3A5C' }
            $progressBg.Background = [System.Windows.Media.BrushConverter]::new().ConvertFrom($progressBgColor)
            $progressBg.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $progressBg.Height = 8
            $progressBg.VerticalAlignment = 'Center'

            $progressFill = New-Object System.Windows.Controls.Border
            $progressFill.CornerRadius = [System.Windows.CornerRadius]::new(4)
            $progressFill.Height = 8
            $progressFill.HorizontalAlignment = 'Left'
            $progressFill.Width = [math]::Max(($pctUsed / 100) * 100, 1)

            if ($pctUsed -ge 90) {
                $progressFill.Background = $window.FindResource("DangerBrush")
            } elseif ($pctUsed -ge 70) {
                $progressFill.Background = $window.FindResource("WarningBrush")
            } else {
                $progressFill.Background = $window.FindResource("SuccessBrush")
            }

            $progressBg.Child = $progressFill
            [System.Windows.Controls.Grid]::SetColumn($progressBg, 1)
            $grid.Children.Add($progressBg)

            # Limit value
            $limitText = New-Object System.Windows.Controls.TextBlock
            $limitText.Text = "$limitMin min/day"
            $limitText.FontSize = 12
            $limitText.Foreground = $window.FindResource("TextSecondaryBrush")
            $limitText.HorizontalAlignment = 'Center'
            $limitText.VerticalAlignment = 'Center'
            [System.Windows.Controls.Grid]::SetColumn($limitText, 2)
            $grid.Children.Add($limitText)

            # Remove button
            $removeBtn = New-Object System.Windows.Controls.Button
            $removeBtn.Content = "Remove"
            $removeBtn.Style = $window.FindResource("DangerButton")
            $removeBtn.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
            $removeBtn.FontSize = 11
            $removeBtn.Tag = $appName
            $removeBtn.Add_Click({
                param($sender, $e)
                $name = $sender.Tag
                $script:Limits.PSObject.Properties.Remove($name)
                # Unblock the app if it was blocked
                $toRemove = @($script:BlockedByLimit.Keys | Where-Object { $script:BlockedByLimit[$_] -eq $name })
                foreach ($key in $toRemove) { $script:BlockedByLimit.Remove($key) }
                Save-JsonData -Path $LimitsFile -Data $script:Limits
                Update-LimitsList
            })
            [System.Windows.Controls.Grid]::SetColumn($removeBtn, 3)
            $grid.Children.Add($removeBtn)

            $border.Child = $grid
            $LimitsListPanel.Children.Add($border)
        }
    }

    if (-not $hasLimits) {
        $noLimits = New-Object System.Windows.Controls.TextBlock
        $noLimits.Text = "No limits set yet. Add a limit above to get started."
        $noLimits.Foreground = $window.FindResource("TextSecondaryBrush")
        $noLimits.FontSize = 12
        $noLimits.FontStyle = 'Italic'
        $LimitsListPanel.Children.Add($noLimits)
    }

    # Quick Set buttons
    $QuickLimitsPanel.Children.Clear()
    $quickApps = @(
        @{Name="Google Chrome"; Process="chrome"; Icon=[char]0xE774},
        @{Name="Microsoft Edge"; Process="msedge"; Icon=[char]0xE774},
        @{Name="Mozilla Firefox"; Process="firefox"; Icon=[char]0xE774},
        @{Name="Visual Studio Code"; Process="Code"; Icon=[char]0xE943},
        @{Name="Microsoft Word"; Process="WINWORD"; Icon=[char]0xE8A5},
        @{Name="Microsoft Excel"; Process="EXCEL"; Icon=[char]0xE9F9},
        @{Name="Spotify"; Process="Spotify"; Icon=[char]0xE8D6},
        @{Name="Discord"; Process="Discord"; Icon=[char]0xE8BD},
        @{Name="Microsoft Teams"; Process="Teams"; Icon=[char]0xE716},
        @{Name="Notepad"; Process="notepad"; Icon=[char]0xE70F}
    )

    foreach ($qa in $quickApps) {
        $btn = New-Object System.Windows.Controls.Button
        $sp = New-Object System.Windows.Controls.StackPanel
        $sp.Orientation = 'Horizontal'
        $iconTb = New-Object System.Windows.Controls.TextBlock
        $iconTb.Text = [string]$qa.Icon
        $iconTb.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
        $iconTb.FontSize = 14
        $iconTb.Margin = [System.Windows.Thickness]::new(0, 0, 8, 0)
        $sp.Children.Add($iconTb)
        $nameTb = New-Object System.Windows.Controls.TextBlock
        $nameTb.Text = "$($qa.Name) (60 min)"
        $nameTb.FontSize = 12
        $sp.Children.Add($nameTb)
        $btn.Content = $sp
        $btn.Style = $window.FindResource("ModernButton")
        $btn.Margin = [System.Windows.Thickness]::new(0, 0, 8, 8)
        $btn.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $btn.Tag = $qa.Process
        $btn.Add_Click({
            param($sender, $e)
            $procName = $sender.Tag
            if (-not $script:Limits.PSObject) {
                $script:Limits = [PSCustomObject]@{}
            }
            $friendlyName = Get-FriendlyAppName -ProcessName $procName
            $script:Limits | Add-Member -NotePropertyName $friendlyName -NotePropertyValue 60 -Force
            Save-JsonData -Path $LimitsFile -Data $script:Limits
            Update-LimitsList
        })
        $QuickLimitsPanel.Children.Add($btn)
    }
}

$AddLimitBtn.Add_Click({
    $appName = $LimitAppName.Text.Trim()
    $minutes = 0
    if ([int]::TryParse($LimitMinutes.Text.Trim(), [ref]$minutes) -and $appName -and $minutes -gt 0) {
        if (-not $script:Limits.PSObject) {
            $script:Limits = [PSCustomObject]@{}
        }
        $script:Limits | Add-Member -NotePropertyName $appName -NotePropertyValue $minutes -Force
        Save-JsonData -Path $LimitsFile -Data $script:Limits
        $LimitAppName.Text = ""
        $LimitMinutes.Text = ""
        Update-LimitsList
    } else {
        [System.Windows.MessageBox]::Show("Please enter a valid app name and number of minutes.",
            "Invalid Input", 'OK', 'Warning')
    }
})

# ── Parental Controls Page ──
function Update-ParentalPage {
    $ParentalEnabledToggle.IsChecked = $script:ParentalConfig.Enabled
    $BedtimeToggle.IsChecked = $script:ParentalConfig.BedtimeEnabled
    $BedtimeStartBox.Text = $script:ParentalConfig.BedtimeStart
    $BedtimeEndBox.Text = $script:ParentalConfig.BedtimeEnd

    if ($script:ParentalConfig.PinHash) {
        $PinStatusText.Text = "PIN is set and active"
        $PinStatusText.Foreground = $window.FindResource("SuccessBrush")
    } else {
        $PinStatusText.Text = "No PIN set - parental controls are not protected"
        $PinStatusText.Foreground = $window.FindResource("WarningBrush")
    }

    # Check if PIN lock should be shown
    if ($script:ParentalConfig.PinHash -and -not $script:ParentalUnlocked) {
        $ParentalLockScreen.Visibility = 'Visible'
        $ParentalContent.Visibility = 'Collapsed'
    } else {
        $ParentalLockScreen.Visibility = 'Collapsed'
        $ParentalContent.Visibility = 'Visible'
    }

    # Blocked apps list
    Update-BlockedAppsList
}

$script:ParentalUnlocked = $false

$PinUnlockBtn.Add_Click({
    $enteredPin = $PinEntryBox.Password
    $hash = Get-HashString $enteredPin
    if ($hash -eq $script:ParentalConfig.PinHash) {
        $script:ParentalUnlocked = $true
        $PinEntryBox.Password = ""
        $PinErrorText.Text = ""
        Update-ParentalPage
    } else {
        $PinErrorText.Text = "Incorrect PIN. Please try again."
        $PinEntryBox.Password = ""
    }
})

$SetPinBtn.Add_Click({
    $pin = $SetPinBox.Password
    if ($pin.Length -ge 4 -and $pin.Length -le 6 -and $pin -match '^\d+$') {
        $script:ParentalConfig.PinHash = Get-HashString $pin
        Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
        $SetPinBox.Password = ""
        $PinStatusText.Text = "PIN has been set successfully"
        $PinStatusText.Foreground = $window.FindResource("SuccessBrush")
        $ChangePinBtn.Visibility = 'Visible'
        $ResetPinBtn.Visibility = 'Visible'
    } else {
        [System.Windows.MessageBox]::Show("PIN must be 4-6 digits.", "Invalid PIN", 'OK', 'Warning')
    }
})

# Show Change/Reset PIN buttons if PIN is already set
if ($script:ParentalConfig.PinHash) {
    $ChangePinBtn.Visibility = 'Visible'
    $ResetPinBtn.Visibility = 'Visible'
}

$ChangePinBtn.Add_Click({
    $ChangePinSection.Visibility = 'Visible'
    $ChangePinBtn.Visibility = 'Collapsed'
    $ResetPinBtn.Visibility = 'Collapsed'
    $OldPinBox.Password = ""
    $NewPinBox.Password = ""
    $ConfirmPinBox.Password = ""
    $ChangePinErrorText.Text = ""
})

$CancelChangePinBtn.Add_Click({
    $ChangePinSection.Visibility = 'Collapsed'
    $ChangePinBtn.Visibility = 'Visible'
    $ResetPinBtn.Visibility = 'Visible'
    $OldPinBox.Password = ""
    $NewPinBox.Password = ""
    $ConfirmPinBox.Password = ""
    $ChangePinErrorText.Text = ""
})

$SaveNewPinBtn.Add_Click({
    $oldPin = $OldPinBox.Password
    $newPin = $NewPinBox.Password
    $confirmPin = $ConfirmPinBox.Password

    # Verify current PIN
    $oldHash = Get-HashString $oldPin
    if ($oldHash -ne $script:ParentalConfig.PinHash) {
        $ChangePinErrorText.Text = "Current PIN is incorrect."
        $OldPinBox.Password = ""
        return
    }

    # Validate new PIN
    if ($newPin.Length -lt 4 -or $newPin.Length -gt 6 -or $newPin -notmatch '^\d+$') {
        $ChangePinErrorText.Text = "New PIN must be 4-6 digits."
        return
    }

    # Confirm match
    if ($newPin -ne $confirmPin) {
        $ChangePinErrorText.Text = "New PIN and Confirm PIN do not match."
        $ConfirmPinBox.Password = ""
        return
    }

    # Save new PIN
    $script:ParentalConfig.PinHash = Get-HashString $newPin
    Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
    $OldPinBox.Password = ""
    $NewPinBox.Password = ""
    $ConfirmPinBox.Password = ""
    $ChangePinErrorText.Text = ""
    $ChangePinSection.Visibility = 'Collapsed'
    $ChangePinBtn.Visibility = 'Visible'
    $ResetPinBtn.Visibility = 'Visible'
    $PinStatusText.Text = "PIN changed successfully"
    $PinStatusText.Foreground = $window.FindResource("SuccessBrush")
    [System.Windows.MessageBox]::Show("PIN has been changed successfully.", "PIN Changed", 'OK', 'Information')
})

# Reset PIN handler
$ResetPinBtn.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Are you sure you want to reset the PIN? This will remove PIN protection from Parental Controls.",
        "Reset PIN",
        'YesNo',
        'Warning'
    )
    if ($result -eq 'Yes') {
        $script:ParentalConfig.PinHash = ""
        Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
        $ChangePinBtn.Visibility = 'Collapsed'
        $ResetPinBtn.Visibility = 'Collapsed'
        $ChangePinSection.Visibility = 'Collapsed'
        $PinStatusText.Text = "PIN has been reset - parental controls are not protected"
        $PinStatusText.Foreground = $window.FindResource("WarningBrush")
        [System.Windows.MessageBox]::Show("PIN has been reset successfully.", "PIN Reset", 'OK', 'Information')
    }
})

$ParentalEnabledToggle.Add_Checked({
    $script:ParentalConfig.Enabled = $true
    Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
})
$ParentalEnabledToggle.Add_Unchecked({
    $script:ParentalConfig.Enabled = $false
    Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
})

$BlockAppBtn.Add_Click({
    $appName = $BlockAppName.Text.Trim()
    if ($appName) {
        if ($script:ParentalConfig.BlockedApps -is [System.Array]) {
            if ($appName -notin $script:ParentalConfig.BlockedApps) {
                $script:ParentalConfig.BlockedApps += $appName
            }
        } else {
            $script:ParentalConfig.BlockedApps = @($appName)
        }
        Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
        $BlockAppName.Text = ""
        Update-BlockedAppsList
    }
})

function Update-BlockedAppsList {
    $BlockedAppsPanel.Children.Clear()
    if ($script:ParentalConfig.BlockedApps -and $script:ParentalConfig.BlockedApps.Count -gt 0) {
        foreach ($app in $script:ParentalConfig.BlockedApps) {
            $border = New-Object System.Windows.Controls.Border
            $border.Background = $window.FindResource("BgSecondaryBrush")
            $border.BorderBrush = $window.FindResource("BorderBrush")
            $border.BorderThickness = [System.Windows.Thickness]::new(1)
            $border.CornerRadius = [System.Windows.CornerRadius]::new(8)
            $border.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
            $border.Margin = [System.Windows.Thickness]::new(0, 0, 0, 4)

            $grid = New-Object System.Windows.Controls.Grid
            $col1 = New-Object System.Windows.Controls.ColumnDefinition
            $col1.Width = [System.Windows.GridLength]::new(1, [System.Windows.GridUnitType]::Star)
            $col2 = New-Object System.Windows.Controls.ColumnDefinition
            $col2.Width = [System.Windows.GridLength]::new(90)
            $grid.ColumnDefinitions.Add($col1)
            $grid.ColumnDefinitions.Add($col2)

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = 'Horizontal'
            $iconTb = New-Object System.Windows.Controls.TextBlock
            $iconTb.Text = [string]([char]0xE711)
            $iconTb.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe MDL2 Assets")
            $iconTb.FontSize = 14
            $iconTb.Foreground = $window.FindResource("DangerBrush")
            $iconTb.Margin = [System.Windows.Thickness]::new(0, 0, 10, 0)
            $iconTb.VerticalAlignment = 'Center'
            $sp.Children.Add($iconTb)

            $nameText = New-Object System.Windows.Controls.TextBlock
            $nameText.Text = $app
            $nameText.FontSize = 13
            $nameText.Foreground = $window.FindResource("TextPrimaryBrush")
            $nameText.VerticalAlignment = 'Center'
            $sp.Children.Add($nameText)
            [System.Windows.Controls.Grid]::SetColumn($sp, 0)
            $grid.Children.Add($sp)

            $unblockBtn = New-Object System.Windows.Controls.Button
            $unblockBtn.Content = "Unblock"
            $unblockBtn.Style = $window.FindResource("ModernButton")
            $unblockBtn.Padding = [System.Windows.Thickness]::new(12, 4, 12, 4)
            $unblockBtn.FontSize = 11
            $unblockBtn.Tag = $app
            $unblockBtn.Add_Click({
                param($sender, $e)
                $name = $sender.Tag
                $script:ParentalConfig.BlockedApps = @($script:ParentalConfig.BlockedApps | Where-Object { $_ -ne $name })
                Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
                Update-BlockedAppsList
            })
            [System.Windows.Controls.Grid]::SetColumn($unblockBtn, 1)
            $grid.Children.Add($unblockBtn)

            $border.Child = $grid
            $BlockedAppsPanel.Children.Add($border)
        }
    } else {
        $noApps = New-Object System.Windows.Controls.TextBlock
        $noApps.Text = "No apps blocked. Add apps above to block them."
        $noApps.Foreground = $window.FindResource("TextSecondaryBrush")
        $noApps.FontSize = 12
        $noApps.FontStyle = 'Italic'
        $BlockedAppsPanel.Children.Add($noApps)
    }
}

$BedtimeToggle.Add_Checked({
    $script:ParentalConfig.BedtimeEnabled = $true
    Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
})
$BedtimeToggle.Add_Unchecked({
    $script:ParentalConfig.BedtimeEnabled = $false
    Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
})

$SaveBedtimeBtn.Add_Click({
    try {
        [DateTime]::ParseExact($BedtimeStartBox.Text, "HH:mm", $null) | Out-Null
        [DateTime]::ParseExact($BedtimeEndBox.Text, "HH:mm", $null) | Out-Null
        $script:ParentalConfig.BedtimeStart = $BedtimeStartBox.Text
        $script:ParentalConfig.BedtimeEnd = $BedtimeEndBox.Text
        Save-JsonData -Path $ParentalFile -Data $script:ParentalConfig
        [System.Windows.MessageBox]::Show("Bedtime schedule saved!", "Success", 'OK', 'Information')
    } catch {
        [System.Windows.MessageBox]::Show("Invalid time format. Use HH:mm (e.g., 22:00).", "Error", 'OK', 'Warning')
    }
})

$GenerateReportBtn.Add_Click({
    $ReportPanel.Children.Clear()

    $headerText = New-Object System.Windows.Controls.TextBlock
    $headerText.Text = "Weekly Usage Report - Generated $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $headerText.FontSize = 14
    $headerText.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Semibold")
    $headerText.Foreground = $window.FindResource("TextPrimaryBrush")
    $headerText.Margin = [System.Windows.Thickness]::new(0, 0, 0, 12)
    $ReportPanel.Children.Add($headerText)

    # Generate 7-day report
    for ($i = 6; $i -ge 0; $i--) {
        $date = (Get-Date).AddDays(-$i)
        $key = $date.ToString("yyyy-MM-dd")
        $dayTotal = 0
        $appList = @()

        if ($script:UsageData.$key) {
            $dayData = $script:UsageData.$key
            if ($dayData -is [PSCustomObject]) {
                foreach ($prop in $dayData.PSObject.Properties) {
                    $dayTotal += $prop.Value
                    $appList += "$($prop.Name): $(Format-Duration $prop.Value)"
                }
            }
        }
        if ($key -eq $script:TodayKey) {
            $dayTotal = $script:TotalScreenTimeToday
            $appList = @()
            foreach ($app in $script:CurrentAppUsage.GetEnumerator()) {
                $appList += "$($app.Key): $(Format-Duration $app.Value)"
            }
        }

        $dayBorder = New-Object System.Windows.Controls.Border
        $dayBorder.Background = $window.FindResource("BgSecondaryBrush")
        $dayBorder.BorderBrush = $window.FindResource("BorderBrush")
        $dayBorder.BorderThickness = [System.Windows.Thickness]::new(1)
        $dayBorder.CornerRadius = [System.Windows.CornerRadius]::new(8)
        $dayBorder.Padding = [System.Windows.Thickness]::new(12, 8, 12, 8)
        $dayBorder.Margin = [System.Windows.Thickness]::new(0, 0, 0, 6)

        $daySp = New-Object System.Windows.Controls.StackPanel
        $dayTitle = New-Object System.Windows.Controls.TextBlock
        $dayTitle.Text = "$($date.ToString('dddd, MMM dd')) - $(Format-Duration $dayTotal)"
        $dayTitle.FontSize = 13
        $dayTitle.Foreground = $window.FindResource("TextPrimaryBrush")
        $dayTitle.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI Semibold")
        $daySp.Children.Add($dayTitle)

        if ($appList.Count -gt 0) {
            $appsText = New-Object System.Windows.Controls.TextBlock
            $appsText.Text = ($appList | Select-Object -First 5) -join " | "
            $appsText.FontSize = 11
            $appsText.Foreground = $window.FindResource("TextSecondaryBrush")
            $appsText.TextWrapping = 'Wrap'
            $appsText.Margin = [System.Windows.Thickness]::new(0, 4, 0, 0)
            $daySp.Children.Add($appsText)
        }

        $dayBorder.Child = $daySp
        $ReportPanel.Children.Add($dayBorder)
    }
})

# ── Settings Page ──
$TrackingToggle.IsChecked = $script:Config.TrackingEnabled
$NotificationsToggle.IsChecked = $script:Config.NotificationsEnabled
$TrayToggle.IsChecked = $script:Config.MinimizeToTray
$DataPathText.Text = "Data stored at: $($script:AppDataPath)"

$TrackingToggle.Add_Checked({
    $script:Config.TrackingEnabled = $true
    Save-JsonData -Path $ConfigFile -Data $script:Config
    $TrackingIndicator.Fill = $window.FindResource("SuccessBrush")
    $TrackingStatusText.Text = "Tracking Active"
})
$TrackingToggle.Add_Unchecked({
    $script:Config.TrackingEnabled = $false
    Save-JsonData -Path $ConfigFile -Data $script:Config
    $TrackingIndicator.Fill = $window.FindResource("DangerBrush")
    $TrackingStatusText.Text = "Tracking Paused"
})

$NotificationsToggle.Add_Checked({
    $script:Config.NotificationsEnabled = $true
    Save-JsonData -Path $ConfigFile -Data $script:Config
})
$NotificationsToggle.Add_Unchecked({
    $script:Config.NotificationsEnabled = $false
    Save-JsonData -Path $ConfigFile -Data $script:Config
})

$TrayToggle.Add_Checked({
    $script:Config.MinimizeToTray = $true
    Save-JsonData -Path $ConfigFile -Data $script:Config
})
$TrayToggle.Add_Unchecked({
    $script:Config.MinimizeToTray = $false
    Save-JsonData -Path $ConfigFile -Data $script:Config
})

# Start with Windows toggle
$StartupToggle.IsChecked = Test-WindowsStartup
$StartupToggle.Add_Checked({
    $script:Config.StartWithWindows = $true
    Set-WindowsStartup -Enable $true
    Save-JsonData -Path $ConfigFile -Data $script:Config
})
$StartupToggle.Add_Unchecked({
    $script:Config.StartWithWindows = $false
    Set-WindowsStartup -Enable $false
    Save-JsonData -Path $ConfigFile -Data $script:Config
})

# Theme ComboBox - set initial value from config and handle changes
$savedTheme = $script:Config.Theme
if ($savedTheme) {
    foreach ($item in $ThemeComboBox.Items) {
        if ($item.Content -eq $savedTheme) {
            $ThemeComboBox.SelectedItem = $item
            break
        }
    }
}

# Apply saved theme on startup (always call to initialize $script:CurrentTheme)
$initTheme = if ($savedTheme) { $savedTheme } else { "Dark" }
Apply-Theme $initTheme

$ThemeComboBox.Add_SelectionChanged({
    $selected = $ThemeComboBox.SelectedItem.Content
    if ($selected) {
        Apply-Theme $selected
    }
})

$ExportDataBtn.Add_Click({
    $saveDialog = New-Object Microsoft.Win32.SaveFileDialog
    $saveDialog.Filter = "JSON Files (*.json)|*.json|All Files (*.*)|*.*"
    $saveDialog.FileName = "DigitalWellbeing_Export_$(Get-Date -Format 'yyyyMMdd').json"
    if ($saveDialog.ShowDialog()) {
        $exportData = @{
            UsageData = $script:UsageData
            Config    = $script:Config
            Limits    = $script:Limits
            Parental  = @{
                Enabled        = $script:ParentalConfig.Enabled
                BedtimeEnabled = $script:ParentalConfig.BedtimeEnabled
                BedtimeStart   = $script:ParentalConfig.BedtimeStart
                BedtimeEnd     = $script:ParentalConfig.BedtimeEnd
                BlockedApps    = $script:ParentalConfig.BlockedApps
            }
            ExportDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        }
        Save-JsonData -Path $saveDialog.FileName -Data $exportData
        [System.Windows.MessageBox]::Show("Data exported successfully!", "Export Complete", 'OK', 'Information')
    }
})

$ClearDataBtn.Add_Click({
    $result = [System.Windows.MessageBox]::Show(
        "Are you sure you want to clear ALL usage data? This action cannot be undone.",
        "Clear Data",
        'YesNo',
        'Warning'
    )
    if ($result -eq 'Yes') {
        $script:UsageData = @{}
        $script:UsageData | Add-Member -NotePropertyName $script:TodayKey -NotePropertyValue @{} -Force
        $script:CurrentAppUsage = @{}
        $script:TotalScreenTimeToday = 0
        Save-JsonData -Path $DataFile -Data $script:UsageData
        Update-Dashboard
        [System.Windows.MessageBox]::Show("All data has been cleared.", "Data Cleared", 'OK', 'Information')
    }
})

# ── User Info ──
try {
    $UserNameText.Text = $env:USERNAME
} catch {
    $UserNameText.Text = "User"
}

# ══════════════════════════════════════════════════════════════════════
# BACKGROUND TIMER - Usage Tracking
# ══════════════════════════════════════════════════════════════════════

$script:TrackingTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:TrackingTimer.Interval = [TimeSpan]::FromSeconds($script:Config.UpdateIntervalSec)
$script:TrackingTimer.Add_Tick({
    if ($script:Config.TrackingEnabled) {
        Update-UsageTracking

        # Update sidebar screen time
        $totalSec = $script:TotalScreenTimeToday
        $hours = [math]::Floor($totalSec / 3600)
        $mins = [math]::Floor(($totalSec % 3600) / 60)
        $ScreenTimeLabel.Text = "${hours}h ${mins}m screen time today"

        # Update tracking detail
        $appCount = $script:CurrentAppUsage.Count
        $TrackingDetailText.Text = "Monitoring $appCount apps"

        # Update tray icon tooltip
        if ($script:TrayIcon) {
            $script:TrayIcon.Text = "Digital Wellbeing - ${hours}h ${mins}m"
            if ($script:TrayStatusItem) {
                $script:TrayStatusItem.Text = "Screen Time: ${hours}h ${mins}m"
            }
        }

        # Auto-refresh current page
        $currentPage = $script:Pages | Where-Object { $_.Visibility -eq 'Visible' }
        if ($currentPage -eq $PageDashboard) { Update-Dashboard }
    }
})
$script:TrackingTimer.Start()

# ── Initial Setup ──
$DashboardDateText.Text = (Get-Date).ToString("dddd, MMMM dd, yyyy")
Update-Dashboard

# ══════════════════════════════════════════════════════════════════════
# SYSTEM TRAY INITIALIZATION & SHOW WINDOW
# ══════════════════════════════════════════════════════════════════════

# Initialize system tray icon
Initialize-TrayIcon

# ── Global Hotkey: Ctrl+Shift+D to bring app to foreground ──
# Uses GetAsyncKeyState polling via a dedicated timer (works even when window is hidden)
$script:HotkeyTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:HotkeyTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$script:HotkeyWasPressed = $false
$script:HotkeyTimer.Add_Tick({
    try {
        $pressed = [KeyboardHelper]::IsCtrlShiftDPressed()
        if ($pressed -and -not $script:HotkeyWasPressed) {
            # Key combo just pressed — bring window to foreground
            $window.Show()
            $window.ShowInTaskbar = $true
            $window.WindowState = 'Normal'
            $window.Activate()
            $window.Topmost = $true
            $window.Topmost = $false
        }
        $script:HotkeyWasPressed = $pressed
    } catch { }
})
$script:HotkeyTimer.Start()

# Background mode: start minimized to tray (for Windows startup)
if ($Background) {
    $window.WindowState = 'Minimized'
    $window.ShowInTaskbar = $false
    $script:TrayIcon.ShowBalloonTip(3000, "Digital Wellbeing", "Running in background. Click tray icon or press Ctrl+Shift+D to open.", [System.Windows.Forms.ToolTipIcon]::Info)
}

$window.ShowDialog() | Out-Null

# Cleanup
if ($script:TrackingTimer) { $script:TrackingTimer.Stop() }
if ($script:HotkeyTimer) { $script:HotkeyTimer.Stop() }
if ($script:TrayIcon) {
    $script:TrayIcon.Visible = $false
    $script:TrayIcon.Dispose()
}
Save-JsonData -Path $DataFile -Data $script:UsageData
Save-JsonData -Path $ConfigFile -Data $script:Config
