# Changelog

All notable changes to Habit Tracker Widget. Versions follow the release tags on GitHub.

## 1.1.0

The data format is unchanged (version 2), so an existing `data.json` keeps working.

### Fixed

- Blinking window shadows. The 3-second tick used to push the widget to the bottom of the z-order every time, and Windows redrew the shadow on each push. It now sinks the widget only when a normal application window sits directly below it, that is, when something was actually raised above it.

### Added

- Crash insulation: unhandled UI-thread exceptions (a bad paint, timer tick or click) are caught and logged instead of ending the process.
- A log file at `%APPDATA%\HabitWidget\widget.log` with start and close lines and recovered errors, trimmed once it passes 200 KB.
- Off-screen guard: a saved position that no longer fits the monitor layout, for example after unplugging a monitor, is moved onto the primary screen at start.
- `CHANGELOG.md`, new screenshots and a social preview image.

The crash insulation, the log and the off-screen guard were pushed to `main` on 2026-06-10 but never shipped in a release. This is the first release that includes them.

### Changed

- README rewritten: install from Releases, usage, configuration, how it works, privacy, troubleshooting.
- `habit_widget.ps1` is saved as UTF-8 with BOM, so Windows PowerShell 5.1 reads it the same way on every system.

## 1.0.0 - 2026-06-09

First public version: multiple goals in one widget, a 20-week grid per goal, a weekly summary row with a per-goal target, per-goal color themes, the dial and the global hotkey Ctrl+Alt+Shift+O, always below other windows, and automatic migration of the older single-goal data file.
