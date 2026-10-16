# Reference review

Research date: October 16, 2026.

## Method and limits

Inspected the installed applications through their visible windows and accessibility trees. Opened ForkLift's settings and its connection-destination menu, then closed settings without changing any preference values. Launched Double Commander for inspection.

No files were copied, moved, renamed, or deleted. No credentials were inspected, no connection was initiated, and no application assets or source code were extracted. File names and existing server addresses visible in the windows are deliberately omitted from this document.

These are observations of the installed apps in their current configurations. They are not exhaustive feature audits or performance measurements. Path Finder's current window showed one file pane and several disabled toolbar controls, so its dual-pane interactions were not tested.

## Installed applications

| Reference | Direct observation | Design implication for Commander4Mac |
| --- | --- | --- |
| Path Finder | A Drop Stack above the sidebar, favorites, a favorites bar, breadcrumbs, file columns, and several browser modules. | Preserve the staging workflow, but use an original shared shelf and a smaller number of permanent interface regions. |
| ForkLift | Independent tab strips above two panes, breadcrumb locations, active-pane accent, sidebar connections and favorites, and a shared toolbar. General settings expose connection destinations: Active Pane, Right Pane, Left Pane. | Destination routing must be explicit. Keep pane focus visible and route commands through one consistent rule. |
| Commander One | Two file tables, per-pane tabs and locations, a connection control, and visible F3 through F8 actions. The current configuration has dark window chrome and light file tables. | Offer discoverable keyboard actions and ensure app-controlled browsing surfaces follow the selected appearance consistently. |
| Double Commander | Two panes with multiple tabs, drive controls, paths, a command line, and a function-key action strip. Its file tables exposed little accessibility structure in this inspection. | Keep the efficient keyboard workflow while giving every file row, selection, and action a meaningful accessibility representation. |

The interface density judgments above are design interpretations, not measured statements about these products' quality or speed.

## Verified workflow references

Path Finder's documented Drop Stack stages references to items from different folders before a later copy or move. That supports the staging use case; Commander4Mac will use its own layout and interaction details. [Cocoatech: Drop Stack](https://support.cocoatech.com/hc/en-us/articles/43505869579796-Drop-Stack-Temporary-Holding-Area-for-Files).

ForkLift documents independent panes, tab bars, favorites, and view choices. Its support page also documents a preference for opening remote connections in a specific pane. [ForkLift manual](https://www.binarynights.com/manual), [ForkLift support](https://binarynights.com/support).

Double Commander documents a locked tab mode that allows directory changes and restores the saved directory after changing tabs. The user confirmed that Commander4Mac should support both locked pins and navigable pins. Exact return timing in our proposed design is a design choice for review. [Double Commander basic help](https://doublecmd.github.io/doc/en/help.html).

Commander One documents tabs, favorites, queued file operations, and remote connection support. These are reference workflows rather than an implementation or asset source. [Commander One features](https://ftp-mac.com/features.html).

Total Commander was not installed or run on this Mac. Its official change history describes returning to a saved base directory by clicking a tab that allows directory changes. [Total Commander change history](https://www.ghisler.com/mailing.htm).

## Platform research

Apple's table view supports selection, editing, columns, type selection, and drag-and-drop customization through its data source and delegate. This is the basis for proposing AppKit file tables. No claim that this architecture is faster than an alternative has been measured. [Apple: NSTableView](https://developer.apple.com/documentation/AppKit/NSTableView?changes=__2&language=objc).

Foundation provides directory enumeration, metadata access, copy, move, and Trash APIs. Commander4Mac must keep potentially blocking file work away from the main UI thread and add its own operation orchestration. [Apple: FileManager](https://developer.apple.com/documentation/foundation/filemanager).

File access can fail for reasons other than App Sandbox, including POSIX permissions, ACLs, and platform protections. If a sandboxed distribution is introduced, persistent access needs correctly managed security-scoped bookmarks. [Apple: Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc).

Apple documents Local Network privacy on macOS, attribution to the responsible app, and unexpected behavior when multiple versions of an app are installed. This reinforces the project's existing requirement for stable signing identities, distinct development identities, and tests in the actual installed application. [Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).

Specific SFTP libraries, WebDAV implementations, and the SMB mounting mechanism have not been selected or validated. Those decisions require focused compatibility and packaging checks before the remote-connection milestone.

## Full Disk Access requirement, October 16 update

The user explicitly requires Full Disk Access in the first local release. The approved direction is direct installation without App Sandbox, with early setup guidance for the installed app. Apple states that the user must grant this privilege in System Settings; an app cannot grant it to itself. Apple's DTS recommends testing the operation the app actually needs and handling errors rather than inspecting the TCC database. [Apple file-access guidance](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox?language=objc), [Apple DTS](https://developer.apple.com/forums/thread/114452).

Apple announced additional explicit user controls around Full Disk Access on October 2, 2026. Recheck behavior on the installed OS during implementation; do not build around private permission databases or a hard-coded global preflight result. [Apple announcement](https://developer.apple.com/news/?id=p6zjojqw).

Read-only tooling discovery found XcodeGen 2.45.4 and a valid Developer ID Application signing identity. No signing certificate, key, or system permission was modified. The Xcode license prerequisite remains unresolved.

## Workspace observations

The project directory was empty and was not inside a Git repository when inspected. There was no existing application or build configuration to preserve.

The local environment reported Apple silicon, macOS 27.0.1, and Xcode 27.0. These are observations of this computer, not release or compatibility recommendations. Toolchain discovery also reported unaccepted Xcode license agreements. No build or launch of Commander4Mac was attempted.
