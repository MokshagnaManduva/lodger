import AppKit
import LodgerEngine

/// Created on demand. Refreshes only on user actions and pack changes.
final class SettingsWindowController: NSWindowController {
    private let app: AppController
    private let characters = NSPopUpButton()
    private let scales = NSPopUpButton()
    private let sound = NSButton(checkboxWithTitle: "Sound", target: nil, action: nil)
    private let volume = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let preview = NSImageView()
    private let details = NSTextField(wrappingLabelWithString: "")
    private let tuning = NSStackView()
    private let remove = NSButton(title: "Remove Character…", target: nil, action: nil)
    private let reset = NSButton(title: "Reset Character Settings", target: nil, action: nil)

    init(app: AppController) {
        self.app = app
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 650))
        let window = NSWindow(contentRect: root.frame, styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = "Lodger Settings"
        window.contentView = root
        super.init(window: window)
        build(in: root)
        app.onChange = { [weak self] in self?.refresh() }
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    private func build(in root: NSView) {
        characters.target = self; characters.action = #selector(characterChanged)
        scales.target = self; scales.action = #selector(scaleChanged)
        sound.target = self; sound.action = #selector(soundChanged)
        volume.target = self; volume.action = #selector(volumeChanged)
        volume.isContinuous = false
        volume.setAccessibilityLabel("Sound volume")
        remove.target = self; remove.action = #selector(removeCharacter)
        reset.target = self; reset.action = #selector(resetCharacter)
        let add = NSButton(title: "Add Character…", target: self, action: #selector(addCharacter))
        let reveal = NSButton(title: "Reveal Characters Folder", target: self, action: #selector(revealFolder))
        let actions = NSStackView(views: [add, remove, reveal])
        actions.spacing = 8
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Character preview")
        preview.widthAnchor.constraint(equalToConstant: 128).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 128).isActive = true
        details.textColor = .secondaryLabelColor
        let info = NSStackView(views: [preview, details])
        info.spacing = 16
        tuning.orientation = .vertical; tuning.alignment = .leading; tuning.spacing = 8
        let title = NSTextField(labelWithString: "Characters")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        let note = NSTextField(wrappingLabelWithString:
            "Imports are validated before replacement. Removed characters go to Trash. Reset restores this character’s size and behaviour defaults.")
        note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize: 12)
        let stack = NSStackView(views: [title, characters, info, actions,
            NSTextField(labelWithString: "Display size"), scales, tuning, reset,
            sound, NSTextField(labelWithString: "Volume"), volume, note])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        // Scrolling keeps arbitrary pack tuning knobs accessible.
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack); scroll.documentView = document; root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
            characters.widthAnchor.constraint(equalToConstant: 300),
            scales.widthAnchor.constraint(equalToConstant: 140),
            volume.widthAnchor.constraint(equalToConstant: 300)
        ])
    }

    func show() {
        app.reload(); refresh()
        NSApp.activate(ignoringOtherApps: true)
        window?.center(); showWindow(nil)
    }

    func refresh() {
        characters.removeAllItems()
        for pack in app.packs {
            characters.addItem(withTitle: pack.pack.identity.name)
            characters.lastItem?.representedObject = pack.pack.identity.id
        }
        if let id = app.activeID, let i = app.packs.firstIndex(where: { $0.pack.identity.id == id }) {
            characters.selectItem(at: i)
        }
        characters.isEnabled = !app.packs.isEmpty
        sound.state = Preferences.audioEnabled ? .on : .off
        volume.doubleValue = Preferences.volume
        volume.isEnabled = Preferences.audioEnabled
        refreshCharacter()
    }

    private var selectedID: String? { characters.selectedItem?.representedObject as? String }

    private func refreshCharacter() {
        scales.removeAllItems()
        for view in tuning.arrangedSubviews { tuning.removeArrangedSubview(view); view.removeFromSuperview() }
        preview.image = nil
        guard let id = selectedID, let loaded = app.packs.first(where: { $0.pack.identity.id == id }) else {
            scales.isEnabled = false; reset.isEnabled = false; remove.isEnabled = false
            details.stringValue = "No characters installed. Add a character to get started."
            return
        }
        let values = app.scales(for: id)
        scales.addItems(withTitles: values.map { "\($0)×" }); scales.isEnabled = !values.isEmpty
        if let i = values.firstIndex(of: app.scale(for: id)) { scales.selectItem(at: i) }
        reset.isEnabled = true; remove.isEnabled = app.removablePack(for: id) != nil
        let pack = loaded.pack
        details.stringValue = "\(pack.identity.name) · \(pack.identity.version)\n\(pack.identity.description ?? "")\n\(pack.identity.license)"
        if let data = try? app.store.previewData(for: loaded) { preview.image = NSImage(data: data) }
        buildControls(for: pack)
    }

    /// One generic control per entry the pack both declares and uses, under the
    /// group headings the pack chose. Nothing here knows what any control means.
    private func buildControls(for pack: Pack) {
        let sliders = Preferences.resolvedTuning(for: pack), toggles = Preferences.resolvedFlags(for: pack)
        let used = pack.referencedControls
        let entries = pack.tuning.filter { used.contains($0.key) }
        let groups = Dictionary(grouping: entries.keys) { entries[$0]?.group ?? "" }
        for group in groups.keys.sorted() {
            let heading = NSTextField(labelWithString: group.isEmpty ? "Behaviour" : group)
            heading.font = .systemFont(ofSize: 13, weight: .semibold)
            tuning.addArrangedSubview(heading)
            let names = (groups[group] ?? []).sorted {
                let a = entries[$0]!, b = entries[$1]!
                return a.isToggle != b.isToggle ? !a.isToggle : a.label.localizedStandardCompare(b.label) == .orderedAscending
            }
            for name in names {
                guard let knob = entries[name] else { continue }
                let id = NSUserInterfaceItemIdentifier(name)
                if knob.isToggle {
                    let box = NSButton(checkboxWithTitle: knob.label, target: self, action: #selector(flagChanged(_:)))
                    box.identifier = id; box.toolTip = knob.description
                    box.state = (toggles[name] ?? false) ? .on : .off
                    tuning.addArrangedSubview(box)
                } else {
                    let label = NSTextField(labelWithString: knob.label)
                    label.widthAnchor.constraint(equalToConstant: 150).isActive = true
                    let value = sliders[name] ?? knob.defaultValue
                    let slider = NSSlider(value: value, minValue: knob.min, maxValue: knob.max,
                                          target: self, action: #selector(tuningChanged(_:)))
                    slider.identifier = id; slider.toolTip = knob.description
                    slider.setAccessibilityLabel(knob.label)
                    slider.widthAnchor.constraint(equalToConstant: 220).isActive = true
                    let readout = NSTextField(labelWithString: ControlFormat.string(value, unit: knob.unit))
                    readout.textColor = .secondaryLabelColor
                    readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    readout.identifier = NSUserInterfaceItemIdentifier("readout." + name)
                    let row = NSStackView(views: [label, slider, readout])
                    row.spacing = 10; row.toolTip = knob.description
                    tuning.addArrangedSubview(row)
                }
            }
        }
    }

    @objc private func characterChanged() { if let id = selectedID { app.activate(id: id) } }
    @objc private func scaleChanged() {
        guard let id = selectedID else { return }
        let values = app.scales(for: id), i = scales.indexOfSelectedItem
        if values.indices.contains(i) { app.setScale(values[i], for: id) }
    }
    @objc private func soundChanged() {
        Preferences.audioEnabled = sound.state == .on
        app.pet?.audio.enabled = Preferences.audioEnabled && (app.pet?.loaded.pack.requires.contains("audio") ?? false)
        volume.isEnabled = Preferences.audioEnabled
    }
    @objc private func volumeChanged() { Preferences.volume = volume.doubleValue; app.pet?.audio.volume = Preferences.volume }
    @objc private func tuningChanged(_ slider: NSSlider) {
        guard let id = selectedID, let name = slider.identifier?.rawValue else { return }
        app.setTuning(slider.doubleValue, name: name, for: id)
        let unit = app.packs.first { $0.pack.identity.id == id }?.pack.tuning[name]?.unit
        let readout = slider.superview?.subviews.first { $0.identifier?.rawValue == "readout." + name } as? NSTextField
        readout?.stringValue = ControlFormat.string(slider.doubleValue, unit: unit)
    }
    @objc private func flagChanged(_ box: NSButton) {
        if let id = selectedID, let name = box.identifier?.rawValue { app.setFlag(box.state == .on, name: name, for: id) }
    }
    @objc private func resetCharacter() { if let id = selectedID { app.reset(id: id) } }
    @objc private func revealFolder() { NSWorkspace.shared.activateFileViewerSelecting([app.installationDirectory]) }
    @objc private func addCharacter() { app.chooseAndInstallPacks(parent: window) }
    @objc private func removeCharacter() {
        guard let id = selectedID else { return }
        let alert = NSAlert(); alert.messageText = "Move this character to Trash?"
        alert.informativeText = "You can restore it from Trash. A bundled character with the same ID will become available again."
        alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try app.remove(id: id) } catch { app.showError(String(describing: error)) }
    }
}

extension AppController {
    func chooseAndInstallPacks(parent: NSWindow? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = "Install"; panel.message = "Choose one or more character pack folders."
        let finish: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let self else { return }
            let messages = self.installPacks(from: panel.urls)
            if !messages.isEmpty { self.showError(messages.joined(separator: "\n")) }
        }
        if let parent { panel.beginSheetModal(for: parent, completionHandler: finish) }
        else { finish(panel.runModal()) }
    }

    func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "Character installation or management notice"
        alert.informativeText = message; alert.alertStyle = .warning; alert.runModal()
    }
}

/// How a slider's value is shown. The pack supplies only a unit hint.
enum ControlFormat {
    static func string(_ value: Double, unit: String?) -> String {
        switch unit {
        case "seconds":
            let seconds = Int(value.rounded())
            if seconds < 60 { return "\(seconds) s" }
            if seconds < 3600 { return seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds / 60) min \(seconds % 60) s" }
            let minutes = (seconds % 3600) / 60
            return minutes == 0 ? "\(seconds / 3600) h" : "\(seconds / 3600) h \(minutes) min"
        case "percent":
            return "\(Int((value * 100).rounded()))%"
        default:
            return String(format: "%.2f", value)
        }
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
