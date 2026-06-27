# Boundless Skies — Native iOS (SwiftUI)

Pure native SwiftUI app for iOS.
No CocoaPods, SPM, or Carthage dependencies: only Apple frameworks
(`AVFoundation`, `CoreHaptics`, `UIKit`, `SwiftUI`).

## Open in Xcode

```bash
open app/BoundlessSkies.xcodeproj
```

Set your **Development Team** in Signing & Capabilities, then run on a device or
simulator (⌘R).

## Requirements

| Setting | Value |
|---------|-------|
| iOS Deployment Target | 17.0+ |
| Swift Language Mode | 6.0 |
| Strict Concurrency | Complete |
| External Dependencies | None |

## Architecture

```
BoundlessSkies/
├── BoundlessSkiesApp.swift      App entry (@main)
├── ContentView.swift            Root navigation + layout
├── Managers/
│   ├── TextToSpeechManager.swift   AVSpeechSynthesizer wrapper
│   └── HapticManager.swift         CoreHaptics + UIKit fallback
├── Models/
│   ├── HapticEvent.swift
│   └── HapticStyle.swift
├── ViewModels/
│   └── SpeechHapticsViewModel.swift   MVVM coordinator
└── Views/
    ├── SpeechControlsSection.swift
    ├── HapticTestSection.swift
    └── SpeakingStatusView.swift
```

## Native Accessibility Foundation

The app uses `TextToSpeechManager` (`AVSpeechSynthesizer`) for spoken data
descriptions and `HapticManager` (`CHHapticEngine` + `UIImpactFeedbackGenerator`)
for haptic light-curve patterns.

## Build from CLI

```bash
cd app
xcodebuild -scheme BoundlessSkies \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build test
```

## Tests

Unit tests live in `BoundlessSkiesTests/` and use the Swift Testing framework.
Run with ⌘U in Xcode or via `xcodebuild test`.
