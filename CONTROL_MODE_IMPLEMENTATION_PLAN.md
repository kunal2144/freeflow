# Control Mode — Clean Implementation Plan

## Problem

The current uncommitted changes on `feat/control-mode` bolted control mode on by duplicating state and methods per mode. This doesn't scale — every new mode would require another set of booleans and duplicate methods.

## Core Insight

**At any time, only ONE mode is recording.** So we need a single state machine with a mode enum, not parallel boolean flags.

## Design

### New enum
```swift
enum RecordingMode {
    case dictation
    case controlMode
}
```

### Unified state model
- `isRecording: Bool` — is ANY mode recording?
- `activeRecordingMode: RecordingMode?` — which mode? nil when not recording
- `activeRecordingTriggerMode: RecordingTriggerMode?` — hold or toggle

### Shared recording lifecycle
- `startRecording(triggerMode:mode:)` — one method for all modes
- `stopAndTranscribe()` — branches on `activeRecordingMode` for post-processing
- `cancelRecording()` — small helper for cancelling in-progress recording

### What differs between modes (only the processing pipeline)
- **Dictation**: Transcription → PostProcessingService → Voice macros → Paste
- **Control Mode**: Transcription → ControlModeService (LLM) → Paste

## Implementation Steps

### Step 1: Revert unnecessary renames

Revert all 26 `dictation`-prefixed renames back to original names in AppState, SetupView, MenuBarView, ShortcutComponents, App.swift. The original names (`isRecording`, `holdShortcut`, `toggleShortcut`, etc.) are clear enough without the prefix.

### Step 2: Remove duplicated state and methods

Remove: `isControlModeRecording`, `controlModeCapturedContext`, `startControlModeRecording()`, `stopAndProcessControlMode()`, `startControlModeContextCapture()`, `cancelDictationRecording()`.

### Step 3: Add RecordingMode enum + activeRecordingMode property

Add the enum in ShortcutBinding.swift (near RecordingTriggerMode). Add `activeRecordingMode` to AppState.

### Step 4: Parameterize recording lifecycle

- `startRecording(triggerMode:mode:)` sets `activeRecordingMode`
- `beginRecording` uses `activeRecordingMode` for overlay label
- `stopAndTranscribe()` branches on mode for processing
- Add small `cancelRecording()` helper

### Step 5: Route shortcut events cleanly

Control mode events handled directly in `handleShortcutEvent` with simple arming. Dictation events use existing session controller. Conflict prevention: if any mode is active, another cannot start.

### Step 6: Revert DictationShortcutSessionController

Remove control mode event cases — controller should not know about control mode.

### Step 7: Keep genuinely new code

These remain unchanged:
- `ControlModeService.swift`
- New ShortcutRole/ShortcutEvent/ShortcutConfiguration cases for control mode
- HotkeyManager control mode binding evaluation
- RecordingOverlay `isControlMode` state and "Control" label
- `ControlModeShortcutEditor` view
- SettingsView control mode shortcuts section
- AppState control mode shortcut properties

## Verification

1. Build: `swift build`
2. Dictation: hold → record → release → transcribe → paste
3. Control mode: hold → record → release → LLM process → paste
4. Conflict: dictation active + control mode trigger → dictation cancels, control mode starts
5. UI: menu bar state, overlay label, settings sections all correct
