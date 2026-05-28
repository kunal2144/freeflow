import Foundation

enum DictationShortcutAction {
    case start(RecordingTriggerMode)
    case stop
    case switchedToToggle
}

final class DictationShortcutSessionController {
    private(set) var activeMode: RecordingTriggerMode?
    private(set) var toggleStopArmed = false

    func handle(event: ShortcutEvent, isTranscribing: Bool) -> DictationShortcutAction? {
        if activeMode == nil {
            guard !isTranscribing else { return nil }
            switch event {
            case .dictationToggleActivated:
                activeMode = .toggle
                toggleStopArmed = false
                return .start(.toggle)
            case .dictationHoldActivated:
                activeMode = .hold
                toggleStopArmed = false
                return .start(.hold)
            case .dictationHoldDeactivated, .dictationToggleDeactivated:
                return nil
            default:
                return nil
            }
        }

        switch activeMode {
        case .hold:
            switch event {
            case .dictationToggleActivated:
                activeMode = .toggle
                toggleStopArmed = false
                return .switchedToToggle
            case .dictationHoldDeactivated:
                reset()
                return .stop
            case .dictationHoldActivated, .dictationToggleDeactivated:
                return nil
            default:
                return nil
            }

        case .toggle:
            switch event {
            case .dictationToggleDeactivated:
                toggleStopArmed = true
                return nil
            case .dictationToggleActivated:
                guard toggleStopArmed else { return nil }
                reset()
                return .stop
            case .dictationHoldActivated, .dictationHoldDeactivated:
                return nil
            default:
                return nil
            }

        case .none:
            return nil
        }
    }

    func beginManual(mode: RecordingTriggerMode) {
        activeMode = mode
        toggleStopArmed = false
    }

    func forceToggleMode() {
        activeMode = .toggle
        toggleStopArmed = false
    }

    func reset() {
        activeMode = nil
        toggleStopArmed = false
    }
}
