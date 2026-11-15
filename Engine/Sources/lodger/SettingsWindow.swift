import AppKit
import LodgerEngine

/// Settings: Character, Behaviour and General tabs.
///
/// Created on demand and refreshed only by user actions and pack changes; there is
/// no timer here. Everything on the Behaviour tab is generated from what the
/// selected pack declares, so this file names no character and no control.
final class SettingsWindowController: NSWindowController {
    private let app: AppController
    private let updates = UpdateChecker()
    private let tabs = NSTabView()

    // Character
    private let characters = NSPopUpButton()
    private let scales = NSPopUpButton()
    private let preview = NSImageView()
    private let details = NSTextField(wrappingLabelWithString: "")
    private let remove = NSButton(title: "Remove Character…", target: nil, action: nil)
    private let reset = NSButton(title: "Reset Character Settings", target: nil, action: nil)

    // Behaviour
    private let behaviourTitle = NSTextField(labelWithString: "")
    private let controls = NSStackView()
    private let resetBehaviour = NSButton(title: "Reset Behaviour", target: nil, action: nil)

    // General
    private let shown = NSButton(checkboxWithTitle: "Show character", target: nil, action: nil)
    private let opacity = NSSlider(value: 1, minValue: Preferences.opacityRange.lowerBound,
                                   maxValue: Preferences.opacityRange.upperBound, target: nil, action: nil)
    private let opacityReadout = NSTextField(labelWithString: "")
    private let stay = NSButton(checkboxWithTitle: "Stay in place", target: nil, action: nil)
    private let calm = NSButton(checkboxWithTitle: "Calmer on battery", target: nil, action: nil)
    private let login = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginNote = NSTextField(wrappingLabelWithString: "")
    private let sound = NSButton(checkboxWithTitle: "Sound", target: nil, action: nil)
    private let volume = NSSlider(value: 0.4, minValue: 0, maxValue: 1, target: nil, action: nil)

    init(app: AppController) {
        self.app = app
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 560))
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

    // MARK: construction

    private func build(in root: NSView) {
        tabs.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            tabs.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            tabs.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
        addTab("Character", identifier: "character", content: characterTab(), scrolls: false)
        addTab("Behaviour", identifier: "behaviour", content: behaviourTab(), scrolls: true)
        addTab("General", identifier: "general", content: generalTab(), scrolls: false)
    }

    private func addTab(_ title: String, identifier: String, content: NSStackView, scrolls: Bool) {
        content.orientation = .vertical; content.alignment = .leading; content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        let page = NSView()
        if scrolls {
            // A pack may declare any number of controls.
            let scroll = NSScrollView()
            scroll.hasVerticalScroller = true; scroll.drawsBackground = false
            scroll.translatesAutoresizingMaskIntoConstraints = false
            let document = SettingsDocumentView()
            document.translatesAutoresizingMaskIntoConstraints = false
            document.addSubview(content); scroll.documentView = document; page.addSubview(scroll)
            NSLayoutConstraint.activate([
                scroll.leadingAnchor.constraint(equalTo: page.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: page.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: page.topAnchor),
                scroll.bottomAnchor.constraint(equalTo: page.bottomAnchor),
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
                content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18)
            ])
        } else {
            page.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 20),
                content.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -20),
                content.topAnchor.constraint(equalTo: page.topAnchor, constant: 18),
                content.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -18)
            ])
        }
        let item = NSTabViewItem(identifier: identifier)
        item.label = title; item.view = page
        tabs.addTabViewItem(item)
    }

    private func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func caption(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = .secondaryLabelColor; label.font = .systemFont(ofSize: 11)
        label.preferredMaxLayoutWidth = 500
        return label
    }

    private func wire(_ control: NSControl, _ action: Selector, id: String) {
        control.target = self; control.action = action
        control.identifier = NSUserInterfaceItemIdentifier(id)
    }

    private func characterTab() -> NSStackView {
        wire(characters, #selector(characterChanged), id: "characters")
        wire(scales, #selector(scaleChanged), id: "scales")
        wire(remove, #selector(removeCharacter), id: "remove")
        wire(reset, #selector(resetCharacter), id: "resetCharacter")
        let add = NSButton(title: "Add Character…", target: self, action: #selector(addCharacter))
        let reveal = NSButton(title: "Reveal Characters Folder", target: self, action: #selector(revealFolder))
        let actions = NSStackView(views: [add, remove, reveal]); actions.spacing = 8
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setAccessibilityLabel("Character preview")
        preview.widthAnchor.constraint(equalToConstant: 128).isActive = true
        preview.heightAnchor.constraint(equalToConstant: 128).isActive = true
        details.textColor = .secondaryLabelColor
        details.preferredMaxLayoutWidth = 360
        let info = NSStackView(views: [preview, details]); info.spacing = 16; info.alignment = .top
        let size = NSStackView(views: [NSTextField(labelWithString: "Display size"), scales]); size.spacing = 10
        characters.widthAnchor.constraint(equalToConstant: 300).isActive = true
        scales.widthAnchor.constraint(equalToConstant: 100).isActive = true
        return NSStackView(views: [
            heading("Character"), characters, info, size, actions, reset,
            caption("Imports are validated before they replace anything. Removed characters go to Trash. Reset restores this character’s size and behaviour defaults.")
        ])
    }

    private func behaviourTab() -> NSStackView {
        behaviourTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        controls.orientation = .vertical; controls.alignment = .leading; controls.spacing = 8
        wire(resetBehaviour, #selector(resetBehaviourPressed), id: "resetBehaviour")
        return NSStackView(views: [
            behaviourTitle,
            caption("These controls come from the character itself. Changes apply straight away and are saved for this character only."),
            controls, resetBehaviour
        ])
    }

    private func generalTab() -> NSStackView {
        wire(shown, #selector(shownChanged), id: "general.shown")
        wire(opacity, #selector(opacityChanged), id: "general.opacity")
        wire(stay, #selector(stayChanged), id: "general.stay")
        wire(calm, #selector(calmChanged), id: "general.calm")
        wire(login, #selector(loginChanged), id: "general.login")
        wire(sound, #selector(soundChanged), id: "general.sound")
        wire(volume, #selector(volumeChanged), id: "general.volume")
        volume.isContinuous = false
        opacity.setAccessibilityLabel("Character opacity")
        volume.setAccessibilityLabel("Sound volume")
        opacity.widthAnchor.constraint(equalToConstant: 220).isActive = true
        volume.widthAnchor.constraint(equalToConstant: 220).isActive = true
        opacityReadout.textColor = .secondaryLabelColor
        opacityReadout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        opacityReadout.identifier = NSUserInterfaceItemIdentifier("general.opacity.readout")
        loginNote.textColor = .secondaryLabelColor; loginNote.font = .systemFont(ofSize: 11)
        loginNote.preferredMaxLayoutWidth = 500
        func row(_ title: String, _ views: NSView...) -> NSStackView {
            let label = NSTextField(labelWithString: title)
            label.widthAnchor.constraint(equalToConstant: 70).isActive = true
            let row = NSStackView(views: [label] + views); row.spacing = 10
            return row
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development build"
        let check = NSButton(title: "Check for Updates…", target: self, action: #selector(checkForUpdates))
        let about = NSStackView(views: [NSTextField(labelWithString: "Lodger \(version)"), check]); about.spacing = 12
        return NSStackView(views: [
            heading("On screen"),
            shown, caption("When hidden, nothing of the character runs. Its place is remembered."),
            row("Opacity", opacity, opacityReadout),
            stay, caption("The character never sets off walking by itself. You can still drag it, and it still walks when you ask it to."),
            heading("Power and startup"),
            calm, caption("On battery power the character changes activity half as often."),
            login, loginNote,
            heading("Sound"),
            sound, row("Volume", volume),
            heading("About"), about
        ])
    }

    // MARK: refresh

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
        refreshGeneral()
        refreshCharacter()
    }

    private func refreshGeneral() {
        shown.state = Preferences.hidden ? .off : .on
        shown.isEnabled = !app.packs.isEmpty
        opacity.doubleValue = Preferences.opacity
        opacityReadout.stringValue = ControlFormat.string(Preferences.opacity, unit: "percent")
        stay.state = Preferences.stayInPlace ? .on : .off
        calm.state = Preferences.calmOnBattery ? .on : .off
        login.isEnabled = app.loginItem.isAvailable
        login.state = app.loginItem.isAvailable && app.loginItem.isEnabled() ? .on : .off
        loginNote.stringValue = app.loginItem.isAvailable
            ? "You can also change this in System Settings › General › Login Items."
            : "Available when Lodger runs as an app rather than from the command line."
        sound.state = Preferences.audioEnabled ? .on : .off
        volume.doubleValue = Preferences.volume
        volume.isEnabled = Preferences.audioEnabled
    }

    private var selectedID: String? { characters.selectedItem?.representedObject as? String }
    private var selectedPack: Pack? {
        guard let id = selectedID else { return nil }
        return app.packs.first { $0.pack.identity.id == id }?.pack
    }

    private func refreshCharacter() {
        scales.removeAllItems()
        for view in controls.arrangedSubviews { controls.removeArrangedSubview(view); view.removeFromSuperview() }
        preview.image = nil
        guard let id = selectedID, let loaded = app.packs.first(where: { $0.pack.identity.id == id }) else {
            scales.isEnabled = false; reset.isEnabled = false; remove.isEnabled = false
            resetBehaviour.isEnabled = false
            details.stringValue = "No characters installed. Add a character to get started."
            behaviourTitle.stringValue = "Behaviour"
            controls.addArrangedSubview(caption("Add a character to see its controls."))
            return
        }
        let values = app.scales(for: id)
        scales.addItems(withTitles: values.map { "\($0)×" }); scales.isEnabled = !values.isEmpty
        if let i = values.firstIndex(of: app.scale(for: id)) { scales.selectItem(at: i) }
        reset.isEnabled = true; remove.isEnabled = app.removablePack(for: id) != nil
        let pack = loaded.pack
        details.stringValue = [
            "\(pack.identity.name) \(pack.identity.version)",
            pack.identity.description ?? "",
            "By \(pack.identity.author) · \(pack.identity.license)",
            app.removablePack(for: id) != nil ? "Installed by you" : "Included with Lodger or a development folder"
        ].filter { !$0.isEmpty }.joined(separator: "\n")
        if let data = try? app.store.previewData(for: loaded) { preview.image = NSImage(data: data) }
        behaviourTitle.stringValue = "\(pack.identity.name)’s behaviour"
        buildControls(for: pack)
    }

    /// One generic control per entry the pack both declares and uses, under the
    /// group headings the pack chose. Nothing here knows what any control means.
    private func buildControls(for pack: Pack) {
        let sliders = Preferences.resolvedTuning(for: pack), toggles = Preferences.resolvedFlags(for: pack)
        let used = pack.referencedControls
        let entries = pack.tuning.filter { used.contains($0.key) }
        resetBehaviour.isEnabled = !entries.isEmpty
        guard !entries.isEmpty else {
            controls.addArrangedSubview(caption("\(pack.identity.name) has no adjustable behaviour."))
            return
        }
        let groups = Dictionary(grouping: entries.keys) { entries[$0]?.group ?? "" }
        for group in groups.keys.sorted() {
            controls.addArrangedSubview(heading(group.isEmpty ? "General" : group))
            let names = (groups[group] ?? []).sorted {
                let a = entries[$0]!, b = entries[$1]!
                return a.isToggle != b.isToggle ? !a.isToggle : a.label.localizedStandardCompare(b.label) == .orderedAscending
            }
            for name in names {
                guard let knob = entries[name] else { continue }
                if knob.isToggle {
                    let box = NSButton(checkboxWithTitle: knob.label, target: self, action: #selector(flagChanged(_:)))
                    box.identifier = NSUserInterfaceItemIdentifier(name); box.toolTip = knob.description
                    box.state = (toggles[name] ?? false) ? .on : .off
                    controls.addArrangedSubview(box)
                } else {
                    let value = sliders[name] ?? knob.defaultValue
                    let label = NSTextField(labelWithString: knob.label)
                    label.widthAnchor.constraint(equalToConstant: 140).isActive = true
                    let slider = NSSlider(value: value, minValue: knob.min, maxValue: knob.max,
                                          target: self, action: #selector(tuningChanged(_:)))
                    slider.identifier = NSUserInterfaceItemIdentifier(name)
                    slider.setAccessibilityLabel(knob.label)
                    slider.widthAnchor.constraint(equalToConstant: 200).isActive = true
                    let readout = NSTextField(labelWithString: ControlFormat.string(value, unit: knob.unit))
                    readout.textColor = .secondaryLabelColor
                    readout.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
                    readout.identifier = NSUserInterfaceItemIdentifier("readout." + name)
                    readout.widthAnchor.constraint(equalToConstant: 84).isActive = true
                    let undo = NSButton(title: "Reset", target: self, action: #selector(resetControl(_:)))
                    undo.controlSize = .small; undo.bezelStyle = .inline
                    undo.identifier = NSUserInterfaceItemIdentifier("reset." + name)
                    undo.setAccessibilityLabel("Reset \(knob.label)")
                    undo.isEnabled = value != knob.defaultValue
                    let row = NSStackView(views: [label, slider, readout, undo])
                    row.spacing = 10
                    for view in [label, slider, readout] as [NSView] { view.toolTip = knob.description }
                    controls.addArrangedSubview(row)
                }
                if let text = knob.description, knob.isToggle { controls.addArrangedSubview(caption(text)) }
            }
        }
    }

    private func sibling<T: NSView>(of view: NSView, _ id: String) -> T? {
        view.superview?.subviews.first { $0.identifier?.rawValue == id } as? T
    }

    // MARK: actions — character

    @objc private func characterChanged() { if let id = selectedID { app.activate(id: id) } }
    @objc private func scaleChanged() {
        guard let id = selectedID else { return }
        let values = app.scales(for: id), i = scales.indexOfSelectedItem
        if values.indices.contains(i) { app.setScale(values[i], for: id) }
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

    // MARK: actions — behaviour

    @objc private func tuningChanged(_ slider: NSSlider) {
        guard let id = selectedID, let name = slider.identifier?.rawValue, let knob = selectedPack?.tuning[name] else { return }
        app.setTuning(slider.doubleValue, name: name, for: id)
        (sibling(of: slider, "readout." + name) as NSTextField?)?.stringValue = ControlFormat.string(slider.doubleValue, unit: knob.unit)
        (sibling(of: slider, "reset." + name) as NSButton?)?.isEnabled = slider.doubleValue != knob.defaultValue
    }
    @objc private func flagChanged(_ box: NSButton) {
        if let id = selectedID, let name = box.identifier?.rawValue { app.setFlag(box.state == .on, name: name, for: id) }
    }
    @objc private func resetControl(_ button: NSButton) {
        guard let id = selectedID, let raw = button.identifier?.rawValue, raw.hasPrefix("reset.") else { return }
        app.resetControl(String(raw.dropFirst("reset.".count)), for: id)
        refreshCharacter()
    }
    @objc private func resetBehaviourPressed() {
        guard let id = selectedID else { return }
        app.resetBehaviour(id: id)
        refreshCharacter()
    }

    // MARK: actions — general

    @objc private func shownChanged() { app.setHidden(shown.state != .on) }
    @objc private func opacityChanged() {
        app.setOpacity(opacity.doubleValue)
        opacityReadout.stringValue = ControlFormat.string(Preferences.opacity, unit: "percent")
    }
    @objc private func stayChanged() { app.setStayInPlace(stay.state == .on) }
    @objc private func calmChanged() { app.setCalmOnBattery(calm.state == .on) }
    @objc private func loginChanged() {
        if let problem = app.setLaunchAtLogin(login.state == .on) { app.showError(problem) }
        refreshGeneral()
    }
    @objc private func soundChanged() {
        Preferences.audioEnabled = sound.state == .on
        app.pet?.audio.enabled = Preferences.audioEnabled && (app.pet?.loaded.pack.requires.contains("audio") ?? false)
        volume.isEnabled = Preferences.audioEnabled
    }
    @objc private func volumeChanged() { Preferences.volume = volume.doubleValue; app.pet?.audio.volume = Preferences.volume }
    @objc private func checkForUpdates() { updates.check() }
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
        let alert = NSAlert(); alert.messageText = "Lodger"
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
