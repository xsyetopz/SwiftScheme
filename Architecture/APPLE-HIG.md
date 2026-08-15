# Apple HIG applicability

- Platform: macOS 14+ terminal process
- Surface: stdin/stdout/stderr; no SwiftUI, UIKit, or AppKit target
- Decision: keep the runtime text-first; do not add a UI target for HIG coverage

The CLI emits semantic, script-safe text and keeps diagnostics on stderr. The
terminal owns typography, contrast, appearance, motion, and accessibility.
If a native UI is added, it must be a separate target with keyboard access,
VoiceOver labels, appearance/accessibility checks, and no dependency from the
interpreter back into the UI.
