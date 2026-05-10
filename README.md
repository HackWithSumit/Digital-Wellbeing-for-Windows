# Digital Wellbeing - PowerShell GUI Application

<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-5.1%2B-blue?style=for-the-badge&logo=powershell&logoColor=white" alt="PowerShell 5.1+"/>
  <img src="https://img.shields.io/badge/Platform-Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/UI-WPF%20%7C%20XAML-purple?style=for-the-badge" alt="WPF | XAML"/>
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" alt="MIT License"/>
</p>

A **high-quality, modern GUI-based Digital Wellbeing application** built entirely with PowerShell and WPF (Windows Presentation Foundation). Monitor your screen time, track application usage, set time limits, and manage parental controls — all from a beautiful dark-themed interface.

---

## Features

### Dashboard
- **Real-time overview** of today's screen time, apps used, and active limits
- **Top applications** with visual usage bars
- **Currently running applications** with memory usage
- **Usage breakdown chart** with daily statistics

### App Usage Tracking
- **Real-time monitoring** of all running applications
- **Third-party app detection** — separates system apps from user-installed apps
- **Search and filter** through running applications
- **Detailed info** — process name, window title, usage time, memory consumption
- **Foreground tracking** — accurately tracks which app you're actively using

### Screen Time
- **Daily total screen time** with live updates
- **Current session duration** tracking
- **Weekly usage chart** — visual bar chart of the past 7 days
- **Hourly activity breakdown** — see your usage patterns throughout the day

### Time Limits
- **Per-application daily limits** — set limits in minutes for any app
- **Visual progress bars** showing usage vs. limit
- **Quick-set buttons** for popular apps (Chrome, VS Code, Discord, etc.)
- **Desktop notifications** when approaching or exceeding limits
- **Add/remove limits** through an intuitive interface

### Parental Controls
- **PIN-protected access** (4-6 digit PIN with SHA-256 hashing)
- **App blocking** — block any application by process name (forcefully closes blocked apps)
- **Bedtime schedule** — set bedtime hours to restrict device usage
- **Weekly usage reports** — generate detailed 7-day usage summaries
- **Enable/disable toggle** with persistent settings

### Settings
- **Toggle tracking** on/off
- **Toggle notifications** on/off
- **Minimize to system tray** option
- **Export data** to JSON file
- **Clear all data** with confirmation

---

## Screenshots

The application features a modern dark theme with:
- Sleek sidebar navigation with active state indicators
- Material Design-inspired color palette (Purple/Pink accent colors)
- Rounded cards with subtle shadows
- Custom toggle switches and progress bars
- Segoe MDL2 icon font for crisp iconography

---

## Requirements

- **Windows 10/11** (or Windows 7/8 with .NET Framework 4.5+)
- **PowerShell 5.1+** (pre-installed on Windows 10/11) or **PowerShell 7+**
- **Run as Administrator** recommended (for full process monitoring and app blocking capabilities)

---

## Installation & Usage

### Quick Start

1. **Download** `DigitalWellbeing.ps1`
2. **Right-click** the file → **Run with PowerShell**

Or run from PowerShell:
```powershell
# Navigate to the directory
cd path\to\DigitalWellbeing-PowerShell

# Run the application
.\DigitalWellbeing.ps1
```

### Run as Administrator (Recommended)
```powershell
# Auto-elevate to admin
.\DigitalWellbeing.ps1 -RunAsAdmin
```

### Reset All Data
```powershell
# Clear all saved data and start fresh
.\DigitalWellbeing.ps1 -ResetData
```

### Execution Policy
If you get an execution policy error:
```powershell
# Allow scripts to run (run as admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Or run directly bypassing policy
powershell.exe -ExecutionPolicy Bypass -File .\DigitalWellbeing.ps1
```

---

## How It Works

### Architecture

```
DigitalWellbeing.ps1
├── Data Layer          — JSON-based persistence in %APPDATA%\DigitalWellbeing
├── Tracking Engine     — Background timer with Win32 API for foreground detection
├── WPF GUI (XAML)      — Modern dark-themed interface with 7 pages
└── Event Handlers      — Navigation, settings, limits, parental controls
```

### Data Storage

All data is stored as JSON files in `%APPDATA%\DigitalWellbeing\`:

| File | Purpose |
|------|---------|
| `usage_data.json` | Daily app usage data (keyed by date) |
| `config.json` | App settings (tracking, notifications, etc.) |
| `limits.json` | Per-app time limits in minutes |
| `parental.json` | Parental control settings, blocked apps, PIN hash |

### Tracking Method

1. A **DispatcherTimer** runs every 5 seconds
2. Uses **Win32 API** (`GetForegroundWindow`, `GetWindowThreadProcessId`) to detect the active app
3. Accumulates usage time per application
4. Saves data to disk periodically
5. Checks time limits and parental controls on each tick

---

## Application Pages

| Page | Description |
|------|-------------|
| **Dashboard** | Overview with stats cards, top apps, usage chart, running apps |
| **App Usage** | Detailed list of all running apps with search/filter |
| **Screen Time** | Daily/weekly/hourly usage charts and statistics |
| **Time Limits** | Set and manage per-app daily time limits |
| **Parental Controls** | PIN lock, app blocking, bedtime schedule, weekly reports |
| **Settings** | Toggle features, export/clear data |
| **About** | App info, version, author, features list |

---

## Parental Controls Guide

### Setting Up PIN Protection

1. Navigate to **Parental Controls**
2. Enter a 4-6 digit PIN in the **PIN Protection** section
3. Click **Set PIN**
4. The next time you visit Parental Controls, you'll need to enter the PIN

### Blocking Applications

1. Enter the **process name** of the app to block (e.g., `chrome`, `discord`, `steam`)
2. Click **Block App**
3. When the blocked app is opened, it will be **forcefully closed** with a notification

### Bedtime Schedule

1. Enable the **Bedtime Schedule** toggle
2. Set **Start Time** and **End Time** (24-hour format, e.g., `22:00` to `07:00`)
3. Click **Save Schedule**
4. During bedtime hours, notifications will remind users to stop using the device

---

## Contributing

Contributions are welcome! Feel free to:
- Report bugs
- Suggest new features
- Submit pull requests

---

## License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

## Author

**Sumit** ([@HackWithSumit](https://github.com/HackWithSumit))

---

<p align="center">
  <i>Built with PowerShell & WPF — No external dependencies required</i>
</p>
