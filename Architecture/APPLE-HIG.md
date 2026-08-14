# Apple HIG applicability: SwiftScheme

**Record type:** applicability and future-surface contract (not a UI
conformance claim)
**Decision date:** 2026-08-14
**Current owner:** Apple-platform design owner (the owner named in
`Architecture/ADR-0001-r5rs-runtime-topology.md`); revisit this file when a
native UI target is proposed.

## Decision

SwiftScheme currently remains a macOS Swift Package Manager library plus
command-line executables. It has no SwiftUI, UIKit, or AppKit surface, so the
Human Interface Guidelines (HIG) are not a current implementation or release
gate for the package. Adding a GUI merely to claim HIG coverage is explicitly
out of scope.

This is the no-native-UI boundary selected by ADR-0001 Candidate B: keep the
single library and terminal CLI text-first, and do not add a UI target or make
the interpreter depend on an Apple UI framework merely for architectural or HIG
coverage.

If a native surface is approved later, it must be a separately named target
with an explicit platform and accessibility contract. The interpreter library
and the existing text CLI remain usable without that target. This record is
therefore an applicability boundary: it captures what must be decided before
there is an interface, rather than asserting that a terminal process is a
macOS GUI application.

## Repository evidence

- `Package.swift` declares Swift tools 6.3, `.macOS(.v14)`, a `SwiftScheme`
  library, the `swiftscheme` executable, and the `SwiftSchemeTests` Swift
  Testing test target.
- `Sources/SwiftSchemeCLI/main.swift` consumes command-line arguments, files,
  standard input, and a TTY; it writes text to standard output/error and has
  no SwiftUI, UIKit, or AppKit import.
- `Sources/swiftscheme` contains the interpreter/runtime library. No source
  target creates windows, views, menus, controls, or other native UI objects.
- `Tests/SwiftSchemeTests` is a Swift Testing test target (`import Testing`);
  there is no self-test executable product.

## Platform, device, input, appearance, and accessibility context

| Context | Current contract | Contract if a native surface is added |
| --- | --- | --- |
| Platform/device | macOS 14 or newer as declared by the package; a Mac desktop or laptop running a terminal process (including pipes and CI). | macOS windowed app on the supported macOS versions; do not imply iOS, iPadOS, watchOS, tvOS, or visionOS support without a new platform decision. |
| Input | `argv`, file paths, stdin, pipes, `readLine()`, and terminal keyboard input. Pointer, touch, Siri, and game-controller input are not package inputs. | Keyboard and pointing-device input are the baseline macOS modes. Add Voice Control, Full Keyboard Access, Switch Control, and other alternatives where controls are introduced. |
| Appearance | The terminal owns colors, contrast, font, and light/dark appearance. SwiftScheme emits semantic text and does not own a palette, layout, animation, or Dynamic Type setting. | Support light/dark and increased-contrast contexts with system-defined colors where visual UI exists; account for user text-size settings and Reduce Motion. |
| Accessibility | The terminal and its assistive technologies (for example, VoiceOver reading terminal text) are the relevant consumer. Keep stdout/stderr text meaningful and script-safe; no accessibility tree exists in this package. | Expose an ordered, labeled accessibility hierarchy and test VoiceOver, keyboard-only navigation, contrast, larger text, and reduced-motion behavior on macOS. |

Apple describes macOS users as working with large displays and combinations of
physical keyboards, pointing devices, game controls, and Siri; it also calls
out windows, the menu bar, keyboard shortcuts, and personalization as native
Mac patterns ([Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/)).
Those recommendations are conditional here because SwiftScheme currently has
none of those visual surfaces.

## Guidance separated by authority

### Current HIG recommendations (authority)

These are Apple recommendations for a future interface, not requirements on
the current CLI:

- HIG fundamentals emphasize hierarchy, harmony, consistency, and platform
  conventions ([Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)).
- An accessible interface should be intuitive, perceivable, and adaptable;
  Apple recommends larger, legible text, sufficient contrast, and descriptions
  for VoiceOver ([Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility),
  [VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover)).
- macOS users expect keyboard operation and standard shortcuts. Full Keyboard
  Access should remain viable and standard shortcuts should not be repurposed
  ([Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards)).
- System typography and text styles should remain legible as text size changes
  ([Typography](https://developer.apple.com/design/human-interface-guidelines/typography)).
  Apple documents Dynamic Type as a system feature on iOS, iPadOS, tvOS,
  visionOS, and watchOS; it is not a current macOS CLI contract.
- System colors adapt to light/dark and increased-contrast contexts; information
  should not be conveyed by color alone ([Color](https://developer.apple.com/design/human-interface-guidelines/color),
  [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)).
- Motion should be purposeful and optional, never the only signal, and should
  account for accessibility settings ([Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
  [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)).

### Implementation requirements (only if a UI target is approved)

1. Add a separately owned macOS UI target and record its supported OS versions,
   inputs, public entry point, and dependency direction. Do not make the core
   interpreter depend on the UI framework.
2. Prefer standard macOS system components (window lifecycle, menu bar,
   toolbar, text editing/console controls, focus handling, system colors, and
   system text styles). Use SwiftUI by default for a new macOS surface; add
   AppKit interop only for a demonstrated system capability gap.
3. Keep every core action keyboard reachable, preserve standard macOS
   shortcuts, and verify Full Keyboard Access. Do not make pointer, gesture,
   color, sound, or animation the sole way to discover or complete an action.
4. Give VoiceOver meaningful labels, roles, values, order, and change
   notifications. Exercise VoiceOver and Switch Control with the actual
   release build rather than inferring accessibility from source alone.
5. Use system text styles and verify readable scaling. Adopt Dynamic Type when
   a future target includes a platform that supports it; for macOS, honor the
   system’s larger-text and accessibility settings instead of inventing a
   package-wide text-size preference.
6. Verify light and dark appearance, Increase Contrast, and (where relevant)
   Reduce Transparency. Use semantic/system colors and pair any color-coded
   status with text, shape, or icon.
7. Keep motion brief, optional, cancelable, and responsive to Reduce Motion;
   use system animations before custom effects. A terminal progress indicator
   is not a reason to add an animated GUI surface.
8. Record UI behavior and accessibility checks in the architecture/test plan.
   Repository tests must continue to use Swift Testing (Swift 6+) rather than
   XCTest; HIG guidance does not prescribe a test framework.

## Inferred design judgment

- **Now:** Keep SwiftScheme text-first. Stable, semantic stdout/stderr is
  useful to scripts, terminal screen readers, and humans, and avoids coupling
  the interpreter to SwiftUI/AppKit. This is repository judgment, not an Apple
  rule.
- **Later:** If users need an interactive editor or inspector, a thin native
  macOS SwiftUI shell over the existing library is the smallest coherent
  addition. Reuse interpreter APIs; keep the CLI and library products intact.
  AppKit should be introduced only for a concrete capability that the selected
  SwiftUI surface cannot provide.
- Dynamic Type, VoiceOver labels, contrast variants, and motion preferences are
  future UI acceptance criteria, not obligations for a process that emits text
  to a terminal owned by another application.

## Rejected alternatives

- **Add SwiftUI/AppKit now:** rejected; there is no product or user-surface
  requirement, and adding a target would increase build and ownership surface
  without improving the CLI contract.
- **Treat the CLI as a GUI and require a full HIG audit today:** rejected; the
  HIG governs Apple-platform interfaces, while the current process exposes
  terminal streams and no accessibility tree.
- **Add ANSI colors, spinners, or animation to simulate HIG feedback:**
  rejected; these can break pipes, snapshots, and terminal accessibility, and
  would make visual effects the only signal for some users.
- **Use a web or UIKit-only front end:** rejected for this decision; it is not
  a native macOS pattern for the declared package and would require a separate
  product/platform decision.

## Evidence status and limits

- **Live HIG source freshness:** **VERIFIED at URL-resolution level** on
  2026-08-14 against the official Apple Developer HIG URLs linked above. The
  text extractor received JavaScript shells for several pages, so complete
  page-content freshness is **UNVERIFIED** in this environment; recheck before
  a UI ships.
- **Behavioral/accessibility evidence:** **UNVERIFIED**. There is no native UI
  target to exercise with Accessibility Inspector, VoiceOver, Full Keyboard
  Access, appearance variants, Dynamic Type, or Reduce Motion.
- **Current CLI evidence:** repository inspection only; no claim is made that
  terminal emulators or their assistive technologies provide identical
  behavior across machines.

This document must be revisited if `Package.swift` gains a native UI target, a
new Apple platform, visual output, or user-facing interaction beyond terminal
streams.
