import AppKit

@MainActor enum FileTableCommandHandler {
    static func command(for event: NSEvent) -> TableCommand? {
        if event.modifierFlags.contains(.command) {
            if event.keyCode == 51 { return .trash }
            if event.keyCode == 126 { return .parent }
            if event.keyCode == 125 { return .open }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": return event.modifierFlags.contains(.option) ? .copyPath : .copyClipboard
            case "v": return event.modifierFlags.contains(.option) ? .moveClipboard : .pasteClipboard
            default: return nil
            }
        }
        switch event.keyCode {
        case 48: return .focusOther
        case 36: return .rename
        case 49: return .preview
        case 96: return .copy
        case 97: return .move
        case 98: return .newFolder
        default: return nil
        }
    }
}
