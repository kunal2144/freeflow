# Control Mode Clean Redesign — Detailed Implementation Plan

## Context

The current uncommitted changes on `feat/control-mode` bolted control mode on top of dictation by:
- Duplicating state variables (`isDictationRecording` + `isControlModeRecording`)
- Duplicating methods (`startControlModeRecording` vs `startRecording`)
- Unnecessarily renaming ~26 variables/methods with `dictation` prefixes

The user's insight: **at any time, only ONE mode is recording**. So we need a single state machine with a mode enum, not parallel boolean flags and duplicated methods per mode.

## Key Design Decision

Introduce a `RecordingMode` enum and keep `isRecording` as a single boolean. The `activeRecordingMode` property tells you *which* mode. All recording lifecycle methods are shared and parameterized by mode. Only the post-recording processing pipeline differs.

## Implementation Plan

### Phase 1: Revert unnecessary renames

Revert all `dictation`-prefixed renames back to original names. These renames added no value — the original names were already clear.

**AppState.swift** — revert these names:
| Current (renamed) | Revert to |
|---|---|
| `isDictationRecording` | `isRecording` |
| `dictationHoldShortcut` | `holdShortcut` |
| `dictationToggleShortcut` | `toggleShortcut` |
| `savedDictationHoldCustomShortcut` | `savedHoldCustomShortcut` |
| `savedDictationToggleCustomShortcut` | `savedToggleCustomShortcut` |
| `dictationHoldShortcutStorageKey` | `holdShortcutStorageKey` |
| `dictationToggleShortcutStorageKey` | `toggleShortcutStorageKey` |
| `savedDictationHoldCustomShortcutStorageKey` | `savedHoldCustomShortcutStorageKey` |
| `savedDictationToggleCustomShortcutStorageKey` | `savedToggleCustomShortcutStorageKey` |
| `activeDictationTriggerMode` | `activeRecordingTriggerMode` |
| `pendingDictationStartTask` | `pendingShortcutStartTask` |
| `pendingDictationStartMode` | `pendingShortcutStartMode` |
| `hasEnabledDictationHoldShortcut` | `hasEnabledHoldShortcut` |
| `hasEnabledDictationToggleShortcut` | `hasEnabledToggleShortcut` |
| `dictationShortcutStatusText` | `shortcutStatusText` |
| `toggleDictationRecording()` | `toggleRecording()` |
| `handleDictationOverlayStopButtonPressed()` | `handleOverlayStopButtonPressed()` |
| `scheduleDictationStart()` | `scheduleShortcutStart()` |
| `cancelPendingDictationStart()` | `cancelPendingShortcutStart()` |
| `startDictationRecording()` | `startRecording()` |
| `stopDictationAndTranscribe()` | `stopAndTranscribe()` |

**SetupView.swift** — revert enum cases, state variables, view builders, and references to use original names.

**MenuBarView.swift, ShortcutComponents.swift, App.swift** — revert all references to use original names.

### Phase 2: Remove duplicated state and methods

**AppState.swift** — remove:
- `isControlModeRecording` (replaced by `isRecording` + `activeRecordingMode`)
- `controlModeCapturedContext` (use existing `capturedContext`)
- `controlModeToggleStopArmed` (keep a single `controlModeToggleArmed` Bool — rename is fine since this is genuinely new)
- `startControlModeRecording()` — absorbed into parameterized `startRecording`
- `stopAndProcessControlMode()` — absorbed into mode-aware branching in `stopAndTranscribe`
- `startControlModeContextCapture()` — use existing `startContextCapture`
- `cancelDictationRecording()` — replaced by small `cancelRecording` helper

### Phase 3: Add RecordingMode enum and unified state

Add new enum (in `ShortcutBinding.swift` near `RecordingTriggerMode`):
```swift
enum RecordingMode {
    case dictation
    case controlMode
}
```

Add to AppState:
```swift
private(set) var activeRecordingMode: RecordingMode?
```

State model becomes:
- `isRecording: Bool` — is ANY mode recording?
- `activeRecordingMode: RecordingMode?` — which mode? nil when not recording
- `activeRecordingTriggerMode: RecordingTriggerMode?` — hold or toggle

### Phase 4: Parameterize recording lifecycle

**`startRecording(triggerMode:mode:)`** — add `mode: RecordingMode = .dictation` parameter. Sets `activeRecordingMode = mode` before calling `beginRecording`.

**`beginRecording(triggerMode:)`** — sets `isRecording = true`, uses `activeRecordingMode` to determine overlay label and status text.

**`stopAndTranscribe()`** — captures `activeRecordingMode` before clearing it, then branches:
- `.dictation` → existing post-processing pipeline (processTranscript, voice macros, etc.)
- `.controlMode` → ControlModeService pipeline (transcribe → LLM → paste)

Shared parts: stop audio, save file, set transcribing state, show overlay, resolve context, paste result, cleanup.

**`cancelRecording()`** — small helper for cancelling in-progress recording (stops audio, resets `isRecording`/`activeRecordingMode`/`activeRecordingTriggerMode`, dismisses overlay).

### Phase 5: Route shortcut events cleanly

Rewrite `handleShortcutEvent`:
- Control mode events handled directly with simple arming logic (not through DictationShortcutSessionController)
- Dictation events use existing session controller
- Conflict prevention: `guard activeRecordingMode != .controlMode` for dictation events, `if isRecording { cancelRecording() }` for control mode events

### Phase 6: Revert DictationShortcutSessionController

Remove control mode event cases from the switch statements — the controller should not know about control mode at all. It returns to its original state.

### Phase 7: Keep genuinely new code (unchanged)

These are genuinely new and remain:
- `ControlModeService.swift` — entirely new
- `ShortcutBinding.swift` — new `controlMode`/`controlModeToggle` cases in `ShortcutRole`, `ShortcutEvent`, `ShortcutConfiguration`
- `HotkeyManager.swift` — new control mode binding evaluation and event emission
- `RecordingOverlay.swift` — `isControlMode` state, "Control" label, stop button hiding
- `ShortcutComponents.swift` — new `ControlModeShortcutEditor` view
- `SettingsView.swift` — new control mode shortcuts section
- AppState — new `controlModeShortcut`, `controlModeToggleShortcut` properties and storage

## Files Modified

| File | Changes |
|---|---|
| `Sources/AppState.swift` | Revert renames, remove duplicates, add `RecordingMode` state, parameterize lifecycle |
| `Sources/App.swift` | Revert `isDictationRecording \|\| isControlModeRecording` to `isRecording` |
| `Sources/MenuBarView.swift` | Revert renamed references, simplify recording checks to `isRecording` |
| `Sources/SetupView.swift` | Revert renamed references |
| `Sources/ShortcutComponents.swift` | Revert dictation shortcut references to original names |
| `Sources/DictationShortcutSessionController.swift` | Remove control mode event cases |
| `Sources/ShortcutBinding.swift` | Add `RecordingMode` enum (new code stays) |
| `Sources/RecordingOverlay.swift` | Unchanged (overlay already uses `isControlMode: Bool`) |

## Verification

1. Build the project: `swift build` or Xcode build
2. Test dictation mode: hold shortcut records, release transcribes and pastes
3. Test control mode: hold shortcut records, release processes via LLM and pastes
4. Test conflict: start dictation, then press control mode shortcut — dictation should cancel, control mode should start
5. Test UI: menu bar shows correct state, overlay shows "Control" for control mode, settings shows both shortcut sections
