# Control Mode Feature — Code Review

## Overview

Review of the control mode feature implementation (branch: `feat/control-mode`), which:
- Renames existing dictation-related variables/methods with `dictation` prefix for clarity
- Adds a new "control mode" feature alongside dictation mode
- Adds `ControlModeService.swift` for LLM-powered instruction processing
- Updates `HotkeyManager`, `ShortcutBinding`, `RecordingOverlay`, `MenuBarView`, `SettingsView`, `SetupView`, and `ShortcutComponents`

**Files changed:** 12 files, +910 / -234 lines

---

## 1. Rename Verification — PASS

All 26 old names have been cleanly renamed across the entire codebase. No stale references found.

### Renamed Variables/Methods

| Old Name | New Name |
|----------|----------|
| `holdShortcut` | `dictationHoldShortcut` |
| `toggleShortcut` | `dictationToggleShortcut` |
| `savedHoldCustomShortcut` | `savedDictationHoldCustomShortcut` |
| `savedToggleCustomShortcut` | `savedDictationToggleCustomShortcut` |
| `holdShortcutStorageKey` | `dictationHoldShortcutStorageKey` |
| `toggleShortcutStorageKey` | `dictationToggleShortcutStorageKey` |
| `savedHoldCustomShortcutStorageKey` | `savedDictationHoldCustomShortcutStorageKey` |
| `savedToggleCustomShortcutStorageKey` | `savedDictationToggleCustomShortcutStorageKey` |
| `isRecording` (AppState) | `isDictationRecording` |
| `activeRecordingTriggerMode` | `activeDictationTriggerMode` |
| `pendingShortcutStartTask` | `pendingDictationStartTask` |
| `pendingShortcutStartMode` | `pendingDictationStartMode` |
| `toggleRecording()` | `toggleDictationRecording()` |
| `stopAndTranscribe()` | `stopDictationAndTranscribe()` |
| `startRecording(triggerMode:)` | `startDictationRecording(triggerMode:)` |
| `handleOverlayStopButtonPressed()` | `handleDictationOverlayStopButtonPressed()` |
| `scheduleShortcutStart(mode:)` | `scheduleDictationStart(mode:)` |
| `cancelPendingShortcutStart(resetMode:)` | `cancelPendingDictationStart(resetMode:)` |
| `shortcutStatusText` | `dictationShortcutStatusText` |
| `hasEnabledHoldShortcut` | `hasEnabledDictationHoldShortcut` |
| `hasEnabledToggleShortcut` | `hasEnabledDictationToggleShortcut` |
| `hotkeySection` (SettingsView) | `dictationModeShortcutsSection` |
| `holdShortcutStep` (SetupView) | `dictationHoldShortcutStep` |
| `toggleShortcutStep` (SetupView) | `dictationToggleShortcutStep` |
| `holdShortcutValidationMessage` | `dictationHoldShortcutValidationMessage` |
| `toggleShortcutValidationMessage` | `dictationToggleShortcutValidationMessage` |

### ShortcutConfiguration Initialization

`ShortcutConfiguration` now requires 4 fields (hold, toggle, controlMode, controlModeToggle). All 3 call sites pass all 4 fields correctly:

| File | Location |
|------|----------|
| `HotkeyManager.swift` | Default value initialization |
| `AppState.swift` | `restartHotkeyMonitoring()` |
| `SetupView.swift` | Test hotkey harness setup |

### Valid `isRecording` References Remaining

`AudioRecorder.isRecording` is a separate property unrelated to the AppState rename — these references are correct.

---

## 2. Dictation Mode Preservation — PASS

All 8 verification points pass:

### 2.1 Start Flow — PASS
- Hold trigger: `handleShortcutEvent` → `.holdActivated` → `DictationShortcutSessionController` → `.start(.hold)` → `scheduleDictationStart` → `startDictationRecording` → `beginRecording`
- Toggle trigger: Same path via `.toggleActivated`
- Properly sets `isDictationRecording`, `activeDictationTriggerMode`, shows overlay

### 2.2 Stop Flow — PASS
- Hold release: `DictationShortcutSessionController` → `.holdDeactivated` → `.stop` → `stopDictationAndTranscribe`
- Toggle tap (when armed): `.toggleActivated` with `toggleStopArmed` → `.stop`
- Overlay stop button: `handleDictationOverlayStopButtonPressed` → `stopDictationAndTranscribe`
- Manual toggle: `toggleDictationRecording` → `stopDictationAndTranscribe`
- Properly clears `isDictationRecording`, `activeDictationTriggerMode`, handles audio

### 2.3 Transcription Pipeline — PASS
- transcribe → format (voice macros + post-processing) → paste at cursor → clipboard restore → cleanup

### 2.4 UI Bindings — PASS
- All UI elements reference renamed properties correctly
- No stale `isRecording` references in AppState, RecordingOverlay, MenuBarView, or DictationShortcutSessionController

### 2.5 Overlay Stop Button — PASS
- Closure chain: `RecordingOverlayManager.onStopButtonPressed` → `AppState.handleDictationOverlayStopButtonPressed` → `stopDictationAndTranscribe`
- Correctly guards on `isDictationRecording && activeDictationTriggerMode == .toggle`

### 2.6 Shortcut Conflict Prevention — PASS
- `setShortcut(_:for:)` cross-validates all 4 shortcut roles against each other
- Menu bar picker also disables conflicting presets

### 2.7 Menu Bar Display — PASS
- Uses `isDictationRecording || isControlModeRecording` for recording state
- Uses `isTranscribing` for transcribing state
- Uses `dictationShortcutStatusText` for ready state

### 2.8 Setup Wizard — PASS
- All setup steps use renamed variables
- Test hotkey harness uses 4-field `ShortcutConfiguration`

---

## 3. Control Mode Implementation — Issues Found

### Correct Behavior Confirmed

- Control mode hold shortcut: press to start, release to process
- Control mode toggle shortcut: tap to start, tap again to stop (arming mechanism)
- Control mode events properly ignored by `DictationShortcutSessionController`
- Control mode activation cancels any active/pending dictation
- `isTranscribing` acts as global lock preventing concurrent recordings
- Overlay correctly shows "Control" label in purple and hides stop button for control mode
- HotkeyManager specificity ordering is correct (most-specific activates first)

### Confirmed Bugs

#### Bug 1: `cancelDictationRecording()` incomplete cleanup
- **Severity:** Low
- **Location:** `AppState.swift`, `cancelDictationRecording()` method
- **Description:** Does not reset `activeDictationTriggerMode` or call `shortcutSessionController.reset()`. Currently safe because the only caller (`controlModeActivated`) does both manually, but it's a maintenance hazard if `cancelDictationRecording` is called from elsewhere in the future.
- **Suggested fix:** Add `activeDictationTriggerMode = nil` and `shortcutSessionController.reset()` to the method body.

#### Bug 2: Quote-stripping logic can mangle legitimate content
- **Severity:** Low-Medium
- **Location:** `ControlModeService.swift`, lines 135-139
- **Description:** The heuristic `hasPrefix("\"") && hasSuffix("\"")` strips outermost quotes from the entire LLM response. If the user's instruction is "put this in quotes" or the output legitimately starts and ends with `"`, those quotes get stripped. The system prompt says "no surrounding quotes" but this is a defensive measure against model disobedience — it can conflict with legitimate quoted output.
- **Suggested fix:** Consider removing the quote stripping and relying solely on the system prompt, or only strip if the response looks like a wrapped string (single-line, short).

#### Bug 3: Simultaneous shortcut activation causes unnecessary work
- **Severity:** Low
- **Location:** `HotkeyManager.swift`, `emitChanges` ordering
- **Description:** When bindings have equal specificity (e.g., both are modifier keys with 0 extra modifiers), dictation activation fires before control mode activation. This causes dictation to briefly start then get immediately cancelled by the control mode handler. Harmless but wasteful.
- **Suggested fix:** Give control mode events priority in the sort (e.g., by adding a secondary sort key for event type).

### Design Concerns (not bugs today)

#### Concern 1: Shared `contextCaptureTask` property
- **Location:** `AppState.swift`
- **Description:** Both dictation's `startContextCapture()` and control mode's `startControlModeContextCapture()` write to the same `contextCaptureTask` property. Currently safe due to mutual exclusion guards (both modes cannot be active simultaneously), but fragile if the code evolves.
- **Recommendation:** Consider separate properties or a shared helper that manages isolation.

#### Concern 2: Dual timeout mechanisms
- **Location:** `ControlModeService.swift`
- **Description:** `URLRequest.timeoutInterval` (20s) and task group timeout (20s) can race, producing inconsistent error types. If URLSession timeout fires first, user sees a URL error; if task group timeout fires first, user sees `ControlModeError.requestTimedOut`.
- **Recommendation:** Set `URLRequest.timeoutInterval` slightly higher than the task group timeout (e.g., 25s) to ensure the task group timeout always fires first with a consistent error message.

---

## Summary

| Area | Status |
|------|--------|
| Rename completeness | All 26 names cleanly renamed, no stale references |
| Dictation mode preservation | Fully functional, all flows intact |
| Control mode — shortcut events | Correct |
| Control mode — recording lifecycle | Correct (1 minor cleanup gap) |
| Control mode — HotkeyManager | Correct (1 minor ordering issue) |
| Control mode — ControlModeService | Functional (1 quote-stripping concern) |
| Control mode — overlay | Correct |
| Shortcut conflict prevention | All 4 roles cross-validated |
| Build verification | Not yet performed |

**Overall:** The refactor is clean and both modes are functionally correct. The identified issues are low-severity and relate to edge cases and maintainability rather than broken functionality.
