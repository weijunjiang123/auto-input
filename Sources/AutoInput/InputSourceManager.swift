import AppKit
import AutoInputCore
import Carbon
import Foundation

final class InputSourceManager {
    func enabledInputSources() -> [InputSourceDescriptor] {
        let sources = copyInputSources(filter: nil)
        let descriptors = sources.compactMap { source -> InputSourceDescriptor? in
            guard let id = stringProperty(source, kTISPropertyInputSourceID) else { return nil }
            let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
            let category = stringProperty(source, kTISPropertyInputSourceCategory)
            let sourceType = stringProperty(source, kTISPropertyInputSourceType)
            let isSelectable = boolProperty(source, kTISPropertyInputSourceIsSelectCapable) ?? false
            let isKeyboard = category == (kTISCategoryKeyboardInputSource as String)
            let isMode = sourceType == (kTISTypeKeyboardInputMode as String)
            let isLayout = sourceType == (kTISTypeKeyboardLayout as String)

            guard isSelectable, isKeyboard, isMode || isLayout else { return nil }
            return InputSourceDescriptor(
                id: id,
                name: name,
                isASCII: boolProperty(source, kTISPropertyInputSourceIsASCIICapable) ?? false
            )
        }

        var seen = Set<String>()
        return descriptors.filter { source in
            guard !seen.contains(source.id) else { return false }
            seen.insert(source.id)
            return true
        }
    }

    func preferredEnglishSource(from sources: [InputSourceDescriptor]) -> InputSourceDescriptor? {
        let preferredNeedles = ["com.apple.keylayout.ABC", "com.apple.keylayout.US", "ABC", "U.S."]
        for needle in preferredNeedles {
            if let match = sources.first(where: { $0.id.contains(needle) || $0.name == needle }) {
                return match
            }
        }
        return sources.first(where: \.isASCII)
    }

    @discardableResult
    func selectInputSource(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let source = copyInputSources(filter: filter).first else { return false }
        return TISSelectInputSource(source) == noErr
    }

    private func copyInputSources(filter: CFDictionary?) -> [TISInputSource] {
        guard let unmanaged = TISCreateInputSourceList(filter, false) else { return [] }
        return unmanaged.takeRetainedValue() as NSArray as? [TISInputSource] ?? []
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
