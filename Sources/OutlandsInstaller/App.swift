import SwiftUI
import AppKit
import OutlandsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    var mainWindow: NSWindow?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.busy == true else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "An operation is running"
        alert.informativeText = "Use Stop operation and wait for cleanup before quitting."
        alert.addButton(withTitle: "Keep open")
        alert.runModal()
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        guard model?.busy == true else { return true }
        mainWindow?.makeKeyAndOrderFront(nil)
        model?.message = "An operation is still running. Use Stop operation before closing the window."
        return false
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.makeKeyAndOrderFront(nil) }
        return true
    }
}

@main
struct OutlandsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    init() {
        if CommandLine.arguments.contains("--self-check") {
            do {
                let recipe = try Recipe.bundled()
                try GameArt.validate()
                print("Outlands Installer \(AppInfo.version): recipe \(recipe.revision), \(recipe.engine.name), \(recipe.template.name)")
                exit(0)
            } catch { fputs("Self-check failed: \(error.localizedDescription)\n", stderr); exit(1) }
        }
    }
    var body: some Scene {
        WindowGroup("Outlands for Mac") {
            InstallerView(model: model)
                .onAppear {
                    delegate.model = model
                    delegate.mainWindow = NSApplication.shared.windows.first { $0.title == "Outlands for Mac" }
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .task { await model.checkUpdates(automatic: true) }
        }
        .defaultSize(width: 960, height: 700)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await model.checkUpdates() } }
                    .disabled(model.checkingUpdate)
            }
        }
    }
}

struct InstallerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    @State private var showLog = false
    @State private var showProcesses = false
    @State private var showLinks = false

    private var installing: Bool { model.busy && model.step != nil }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                GeometryReader { viewport in
                    ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        page
                        if model.busy || showLog || model.section == "diagnostics" {
                            DisclosureGroup("Operation log", isExpanded: $showLog) {
                                ScrollView {
                                    Text(model.logText.isEmpty ? "No output yet." : model.logText)
                                        .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.frame(height: 180)
                            }
                        }
                    }
                    .padding(.horizontal, 32).padding(.top, 24).padding(.bottom, 20)
                    .frame(width: viewport.size.width, alignment: .leading)
                    }
                }
                statusBar
            }
        }
        .frame(minWidth: 940, minHeight: 700)
        .background(Palette.window)
        .tint(Palette.accent)
        .onAppear { applyAppearance() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, !model.busy { Task { await model.refreshLocalFiles() }; model.refreshBackupStatus() }
        }
        .onChange(of: appearance) { _, _ in applyAppearance() }
        .onChange(of: model.section) { _, section in if section == "backups" { model.refreshBackupStatus() } }
        .sheet(isPresented: $model.showReport) { reportSheet }
        .sheet(isPresented: $model.showBackupPreview) { backupPreviewSheet }
        .sheet(isPresented: $model.showSettingsImport) { settingsImportSheet }
    }

    private func applyAppearance() {
        // NSApp.appearance reliably returns to the system setting; preferredColorScheme(nil) does not.
        switch appearance {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    // MARK: Page

    @ViewBuilder private var page: some View {
        switch model.section {
        case "backups":
            PageHeader(title: "Keep your world safe.") {
                Button("Add existing…") { model.chooseBackup(restore: false) }.buttonStyle(.action)
                Button("Restore…") { model.chooseBackup(restore: true) }.buttonStyle(.action)
                Button("Create backup…") { model.previewBackup() }.keyboardShortcut("b", modifiers: .command).buttonStyle(.action(.primary)).disabled(!model.installed)
            }.disabled(model.busy)
            operationCards
            backups.disabled(model.busy)
        case "diagnostics":
            PageHeader(title: "Everything in view.") {
                Button("Open logs") { model.revealLogs() }.buttonStyle(.action)
                Button("Export…") { model.exportLog() }.buttonStyle(.action)
                Button("Run checks") { model.diagnose() }.buttonStyle(.action(.primary))
            }.disabled(model.busy)
            operationCards
            diagnostics.disabled(model.busy)
        case "settings":
            PageHeader(title: "Make yourself at home.")
            operationCards
            settings
        default:
            if installing {
                PageHeader(title: "Installing Outlands", lead: "You can keep using your Mac. Your current installation stays untouched until the new copy passes its checks.")
                if let failure = model.failure { failureCard(failure) }
                installingView
            } else if model.installed {
                PageHeader(title: "Welcome back.")
                operationCards
                installedView.disabled(model.busy)
            } else {
                PageHeader(title: "Your adventure starts here.", lead: "Outlands gets its own Mac app. Other Wine apps on this Mac are not touched.")
                operationCards
                firstRunView.disabled(model.busy)
            }
        }
    }

    @ViewBuilder private var operationCards: some View {
        if model.busy && !installing {
            Card {
                HStack(spacing: 14) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.activity).fontWeight(.semibold)
                        Text(model.message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if model.elapsed > 0 { Text(elapsedText).font(.callout.monospacedDigit()).foregroundStyle(.secondary) }
                    Button("Stop", role: .destructive) { model.cancel() }.buttonStyle(.action(.danger))
                }
                if model.preventsIdleSleep {
                    Text("Automatic idle sleep is paused while this operation runs.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        if !model.busy, let result = model.resultURL {
            Notice(color: Palette.accent) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.resultTitle).fontWeight(.medium)
                }
                Spacer(minLength: 0)
                Button("Show result") { NSWorkspace.shared.activateFileViewerSelecting([result]) }.buttonStyle(.action(small: true))
                Button("Dismiss") { model.resultURL = nil }.buttonStyle(.action(small: true))
            }
        }
        if let failure = model.failure { failureCard(failure) }
    }

    private func failureCard(_ failure: String) -> some View {
        Notice(color: Palette.warning) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Needs attention").fontWeight(.semibold).foregroundStyle(Palette.warning)
                Text(failure).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Prepare problem report…") { model.prepareReport() }.buttonStyle(.action(small: true))
                    if failure.lowercased().contains("space") {
                        Button("Review backup size…") { model.section = "backups"; model.previewBackup() }.buttonStyle(.action(small: true))
                    } else if failure.lowercased().contains("changed") {
                        Button("Review recovered settings…") { model.reviewSettingsImport() }.buttonStyle(.action(small: true)).disabled(model.restoredFolder == nil)
                    } else if failure.lowercased().contains("closed") || failure.lowercased().contains("running") {
                        Button("Check processes") { model.section = "diagnostics"; model.diagnose() }.buttonStyle(.action(small: true))
                    }
                    Button("Dismiss") { model.failure = nil }.buttonStyle(.action(small: true))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var elapsedText: String { "\(model.elapsed / 60) m \(model.elapsed % 60) s" }

    // MARK: Sidebar and status bar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                if let emblem = GameArt.emblem {
                    Image(nsImage: emblem).resizable().scaledToFit().frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Outlands").font(.system(size: 15, weight: .bold))
                    Text("for Mac").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 6).accessibilityElement(children: .combine)
            VStack(spacing: 2) {
                nav("game", "Game", .castle)
                nav("backups", "Backups", .chest)
                nav("diagnostics", "Diagnostics", .spyglass)
                nav("settings", "Settings", .cog)
            }
            Spacer()
            backupSummary
            Text("Version \(AppInfo.version) \(AppInfo.channel)").font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 6)
        }
        .padding(.horizontal, 14).padding(.top, 18).padding(.bottom, 16)
        .frame(width: 210, alignment: .leading).frame(maxHeight: .infinity)
        .background(Palette.sidebar)
    }

    private func nav(_ section: String, _ title: String, _ icon: GameGlyph) -> some View {
        let selected = model.section == section
        return Button { model.section = section } label: {
            GameLabel(title: title, glyph: icon).font(.body.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 8)
                .background(selected ? Palette.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(selected ? Palette.accent : .secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(NavigationButtonStyle())
        .keyboardShortcut(KeyEquivalent(section == "game" ? "1" : section == "backups" ? "2" : section == "diagnostics" ? "3" : "4"), modifiers: .command)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var backupSummary: some View {
        let last = model.lastBackup
        let availability = last.flatMap { model.backupStatus[$0.url.path] }
        let color = last == nil ? Palette.neutral : availability == .available ? (model.backupReminder ? Palette.warning : Palette.accent) : Palette.warning
        let title = last == nil ? "No backups yet" : "Last backup"
        let detail: String
        if let last {
            switch availability {
            case .missing: detail = "Archive not found"
            case .diskDisconnected: detail = "Connect the backup disk"
            case nil, .checking: detail = "Checking availability…"
            case .available:
                detail = last.created.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))) + (last.verified == nil ? "" : " · previously verified")
            }
        } else {
            detail = model.installed ? "Create one in Backups" : "Available after install"
        }
        return Button { model.section = "backups" } label: {
            HStack(alignment: .top, spacing: 9) {
                StatusDot(color: color).padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).foregroundStyle(.secondary)
                    Text(detail).fontWeight(.semibold)
                }
                Spacer(minLength: 0)
            }
            .font(.caption).padding(10)
            .background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.border))
            .contentShape(Rectangle())
        }.buttonStyle(NavigationButtonStyle())
    }

    /// One place for global operation status, so a message from one page does not read as part of another.
    private var statusBar: some View {
        let color = model.busy ? Palette.accent : model.failure != nil ? Palette.warning : Palette.accent
        let text = model.failure != nil && !model.busy ? "Needs attention · " + model.message : model.message
        return HStack(spacing: 8) {
            StatusDot(color: color)
            Text(text).lineLimit(1).truncationMode(.tail).help(text)
            Spacer(minLength: 12)
            if model.busy {
                ProgressView().controlSize(.mini)
                if model.elapsed > 0 { Text(elapsedText).monospacedDigit() }
            } else {
                Text("No operation running")
            }
        }
        .font(.caption).foregroundStyle(.secondary)
        .padding(.horizontal, 20).frame(height: 30)
        .background(Palette.statusBar)
        .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Game

    private var health: (color: Color, title: String, detail: String) {
        guard !model.checks.isEmpty else {
            return (Palette.neutral, "Installation found", "Local checks pending · Game startup not verified")
        }
        let failed = model.checks.filter { $0.severity == .failure || $0.severity == .warning }
        let time = model.lastCheck.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        let notes = model.checks.filter { $0.severity == .information }.count
        if failed.isEmpty && notes > 0 { return (Palette.neutral, "Local checks complete", "\(model.checks.filter(\.passed).count) verified · \(notes) runtime notes · Game startup not verified" + time) }
        if failed.isEmpty { return (Palette.accent, "Local checks passed", "Files and runtimes checked · Game startup not verified" + time) }
        return (Palette.warning, failed.count == 1 ? "Installed · 1 item needs attention" : "Installed · \(failed.count) items need attention",
                failed.map(\.title).joined(separator: ", ") + time)
    }

    private var installedView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Card(padding: 20) {
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            StatusDot(color: health.color)
                            Text(health.title).font(.system(size: 15, weight: .semibold))
                        }
                        Text(health.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button("Check installation") { model.diagnose(); model.section = "diagnostics" }.buttonStyle(.action)
                    Button { model.openLauncher() } label: { Label("Open Outlands", systemImage: "play.fill") }
                        .buttonStyle(.action(.primary, large: true))
                        .keyboardShortcut(.defaultAction)
                }
            }
            Notice(color: Palette.warning) {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warning).accessibilityHidden(true)
                Text("**Beta.** Launcher start-up on a fresh install is still being verified.")
                Spacer(minLength: 0)
                Button("Make a backup first") { model.section = "backups" }.buttonStyle(LinkButtonStyle())
            }
            Card {
                Text("Open in Finder").font(.headline)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                    folder(.game, "Game files", "Ultima Online Outlands")
                    folder(.scripts, "Razor scripts", "Razor › Scripts")
                    folder(.profiles, "Razor profiles", "Razor › Profiles")
                    folder(.razor, "Razor settings", "Razor folder")
                    folder(.contents, "Package contents", "outlands.app › Contents")
                    folder(.backups, "Installation backups", "Kept by rebuilds")
                }
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ActionRow(title: "Rebuild installation",
                              detail: "Builds a fresh copy and keeps the current one as a backup. Needs 30 GB free.") {
                        Button("Rebuild…") { model.start(rebuild: true) }.buttonStyle(.action(.warning))
                    }
                    Divider()
                    ActionRow(title: "Close Outlands processes",
                              detail: "Force-quits this installation's Wine processes only. Unsaved game or script changes may be lost.") {
                        Button("Close processes…", role: .destructive) { model.stopGame() }.buttonStyle(.action(.danger))
                    }
                }.padding(.horizontal, 20)
            }
            stagingNotice
        }
    }

    private func folder(_ kind: GameFolder, _ title: String, _ detail: String) -> some View {
        Button { model.openFolder(kind) } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").foregroundStyle(Palette.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                    Text(detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityLabel("Open \(title) in Finder")
    }

    @ViewBuilder private var stagingNotice: some View {
        if model.stagingAvailable {
            Notice(color: Palette.neutral) {
                Text("An unfinished installation copy is kept from an earlier attempt.").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Show staged files") { model.revealStaging() }.buttonStyle(.action(small: true))
                Button("Preserve staging & start fresh") { model.discardStaging() }.buttonStyle(.action(small: true))
            }
        }
    }

    private var firstRunView: some View {
        let req = model.requirements
        let rosettaMissing = req.rosetta == false
        let blocked = req.blocking || (rosettaMissing && !model.acceptRosetta) || req.rosetta == nil
        let hint: String
        if req.blocking { hint = "This Mac does not meet the requirements above." }
        else if req.rosetta == nil { hint = "Checking for Rosetta…" }
        else if rosettaMissing && !model.acceptRosetta { hint = "Turn on the Rosetta option to continue." }
        else { hint = "About 10 minutes. Your Mac stays awake while it runs." }
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    requirement("Apple Silicon", req.appleSilicon ? req.chip : "Intel Mac", passed: req.appleSilicon)
                    Divider()
                    requirement("macOS 14.6 or later", req.system, passed: req.systemSupported)
                    Divider()
                    requirement("20 GB free space", ByteCountFormatter.string(fromByteCount: req.freeBytes, countStyle: .file) + " free", passed: req.enoughSpace)
                    Divider()
                    requirement("Rosetta 2", req.rosetta == nil ? "Checking…" : rosettaMissing ? "Not installed" : "Installed", passed: req.rosetta)
                    if rosettaMissing {
                        HStack(spacing: 10) {
                            Toggle("Install Rosetta during setup and accept Apple's software licence", isOn: $model.acceptRosetta)
                                .toggleStyle(.switch).controlSize(.small)
                            Spacer(minLength: 0)
                            Button("Read licence") { NSWorkspace.shared.open(URL(string: "https://www.apple.com/legal/sla/")!) }
                                .buttonStyle(LinkButtonStyle(small: true))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
                        .padding(.leading, 34).padding(.bottom, 12)
                    }
                }.padding(.horizontal, 18)
            }
            Card {
                Text("What gets installed").font(.headline)
                HStack(alignment: .top, spacing: 10) {
                    part("Wine engine", "Sikarugir Wine engine, pinned and checksum-verified")
                    part("Windows runtimes", ".NET Framework for the launcher and Razor")
                    part("Official launcher", "Downloads and verifies the game itself")
                }
            }
            HStack(spacing: 16) {
                Button(model.failure == nil ? "Install Outlands" : "Retry installation") { model.start() }
                    .buttonStyle(.action(.primary, large: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocked)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            stagingNotice
            Text("Community macOS support, not affiliated with Outlands. Installation checks do not certify gameplay.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func requirement(_ title: String, _ value: String, passed: Bool?) -> some View {
        let color = passed == nil ? Palette.neutral : passed == true ? Palette.accent : Palette.warning
        return HStack(spacing: 12) {
            Image(systemName: passed == nil ? "circle.dotted" : passed == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.system(size: 18)).foregroundStyle(color).frame(width: 22).accessibilityHidden(true)
            Text(title)
            Spacer()
            if passed == false { Badge(text: value, color: Palette.warning) }
            else { Text(value).font(.callout).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityValue(passed == nil ? "Checking" : passed == true ? "Passed" : "Needs attention")
    }

    private func part(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 9))
    }

    private var installingView: some View {
        let steps = InstallStep.allCases
        let current = model.step.flatMap { steps.firstIndex(of: $0) } ?? 0
        return VStack(alignment: .leading, spacing: 16) {
            Card(padding: 22) {
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            stepRow(index: index, title: step.rawValue, current: current)
                        }
                    }.frame(width: 230, alignment: .leading)
                    Rectangle().fill(Palette.border).frame(width: 1)
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Step \(current + 1) of \(steps.count)").font(.caption).foregroundStyle(.secondary)
                            Text(steps[current].rawValue).font(.system(size: 17, weight: .semibold))
                            Text(model.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        ProgressView().progressViewStyle(.linear)
                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                            GridRow { Text("Elapsed").foregroundStyle(.secondary); Text(elapsedText).monospacedDigit() }
                            GridRow { Text("Sleep").foregroundStyle(.secondary); Text("Paused until the operation finishes") }
                            GridRow { Text("If you stop").foregroundStyle(.secondary); Text("Staged files are kept so you can retry.") }
                        }.font(.callout)
                        HStack(spacing: 10) {
                            Button("Stop installation", role: .destructive) { model.cancel() }.buttonStyle(.action(.danger))
                            Button("Show logs") { model.revealLogs() }.buttonStyle(.action)
                        }
                    }
                }
            }
        }
    }

    private func stepRow(index: Int, title: String, current: Int) -> some View {
        let done = index < current, active = index == current
        return HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(Palette.accent)
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.onAccent)
                } else {
                    Circle().strokeBorder(active ? Palette.accent : Palette.neutral, lineWidth: active ? 2 : 1.5)
                    Text("\(index + 1)").font(.caption2.weight(.semibold)).foregroundStyle(active ? Palette.accent : .secondary)
                }
            }.frame(width: 22, height: 22)
            Text(title).fontWeight(active ? .semibold : .regular).foregroundStyle(done || active ? .primary : .secondary)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "Done" : active ? "In progress" : "Not started")
    }

    // MARK: Backups

    private var backups: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text("Backup content").fontWeight(.medium)
                Picker("Backup content", selection: $model.backupKind) {
                    Text("Settings & scripts").tag(BackupKind.settings)
                    Text("Full installation").tag(BackupKind.full)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
                Spacer(minLength: 0)
            }
            Text(model.backupKind == .settings
                 ? "Recommended: character profiles, hotkeys, interface settings, Razor scripts, macros and configuration. Game downloads and Wine are excluded."
                 : "Optional recovery copy of the complete application, including downloaded game files. Requires much more space.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { backupScopeChips }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { backupScopeChips }
            }
            if model.installed && model.backupReminder {
                Notice(color: Palette.warning) {
                    Image(systemName: "clock.badge.exclamationmark").foregroundStyle(Palette.warning).accessibilityHidden(true)
                    Text("No recent backup is available. Save one to another disk.")
                    Spacer(minLength: 0)
                }
            }
            if model.settingsRecoveryNeedsReview {
                Notice(color: Palette.warning) {
                    Text("An interrupted settings operation needs recovery. Close the game first.").font(.callout)
                    Spacer()
                    Button("Show folder") { model.openFolder(.game) }.buttonStyle(.action(small: true))
                    Button("Recover…") { model.recoverSettingsTransaction() }.buttonStyle(.action(.warning, small: true))
                }
            }
            if let previous = model.undoSettingsFolder {
                Notice(color: Palette.accent) {
                    Text("A previous configuration is preserved. Undo also keeps your current files.").font(.callout)
                    Spacer(minLength: 0)
                    Button("Show previous") { NSWorkspace.shared.activateFileViewerSelecting([previous]) }.buttonStyle(.action(small: true))
                    Button("Undo restore…") { model.undoSettings() }.buttonStyle(.action(.warning, small: true))
                }
            }
            if let restored = model.restoredFolder {
                Notice(color: Palette.accent) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.restoredKind == .settings ? "Recovered settings are ready" : "A restored copy is ready").fontWeight(.semibold)
                        Text(model.restoredKind == .settings ? "Review recovered files and select what to apply. Your current settings are unchanged until you confirm." : "Activating swaps it in and keeps your current installation as a backup.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([restored]) }.buttonStyle(.action(small: true))
                    Button("Dismiss") { model.dismissRecoveredCopy() }.buttonStyle(.action(small: true)).help("Hide this notice; recovered files stay on disk.")
                    if model.restoredKind == .settings {
                        Button("Review & apply…") { model.reviewSettingsImport() }.buttonStyle(.action(.warning, small: true)).disabled(!model.installed)
                    }
                    if model.restoredKind == .full {
                        Button("Activate…") { model.activateRestored() }.buttonStyle(.action(.warning, small: true))
                    }
                }
            }
            HStack {
                Text("Backup collection").font(.headline)
                Spacer()
                Picker("Sort", selection: $model.catalogSort) {
                    Text("Newest first").tag("newest")
                    Text("Oldest first").tag("oldest")
                    Text("Largest first").tag("size")
                }.frame(width: 190).onChange(of: model.catalogSort) { _, _ in model.sortCatalog() }
                Button("Refresh locations") { model.refreshBackupStatus() }.buttonStyle(.action(small: true))
            }
            if model.backupRecords.isEmpty {
                Card {
                    Text("Your backup collection starts here.").font(.headline)
                    Text("Back up settings and scripts, or add an existing archive. Choose Full installation only when you need the entire game.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else {
                Card(padding: 0) {
                    ViewThatFits(in: .horizontal) {
                        backupTable.frame(minWidth: 780)
                        compactBackupList
                    }.padding(.horizontal, 18).padding(.vertical, 12)
                }
            }
            Text("The catalog remembers locations, not backup contents. If a backup was moved, use Locate. Removing an entry never deletes files. Restore always creates a separate copy.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var backupTable: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
            GridRow {
                Text("BACKUP"); Text("SIZE"); Text("STATUS"); Text("NOTE"); Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary).padding(.bottom, 8)
            ForEach($model.backupRecords) { $record in
                let status = model.backupStatus[record.url.path] ?? .checking
                Divider()
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        TextField(record.created.formatted(date: .abbreviated, time: .shortened), text: Binding(
                            get: { record.name ?? "" }, set: { record.name = $0; model.saveCatalog() }))
                            .textFieldStyle(.plain).fontWeight(.semibold).accessibilityLabel("Backup name")
                            .frame(minWidth: 135, maxWidth: 180)
                        Text(record.scope.title + " · " + location(record.url)).font(.caption).foregroundStyle(.secondary)
                    }.help(record.url.path)
                    Text(ByteCountFormatter.string(fromByteCount: record.bytes, countStyle: .file)).monospacedDigit()
                    VStack(alignment: .leading, spacing: 3) {
                        backupBadge(record, status)
                        Text(record.verified.map { "Last check " + $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_US"))) } ?? "Integrity not checked")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Add a note", text: $record.note)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 110, maxWidth: .infinity)
                        .onSubmit { model.saveCatalog() }
                        .onChange(of: record.note) { _, _ in model.saveCatalog() }
                    backupActions(record, status)
                }.padding(.vertical, 10)
            }
        }
    }

    @ViewBuilder private var backupScopeChips: some View {
        InfoChip(systemImage: "checkmark", text: model.backupKind == .settings ? "Profiles, scripts & settings" : "Entire game and Wine runtime")
        InfoChip(systemImage: "lock.open", text: "Local and unencrypted")
        InfoChip(systemImage: "link", text: "Folders linked from outside are not included")
    }

    private var compactBackupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach($model.backupRecords) { $record in
                let status = model.backupStatus[record.url.path] ?? .checking
                if record.id != model.backupRecords.first?.id { Divider() }
                VStack(alignment: .leading, spacing: 10) {
                    TextField(record.created.formatted(date: .abbreviated, time: .shortened), text: Binding(
                        get: { record.name ?? "" }, set: { record.name = $0; model.saveCatalog() }))
                        .textFieldStyle(.plain).fontWeight(.semibold).accessibilityLabel("Backup name")
                        .help(record.url.path)
                    Text(record.scope.title + " · " + location(record.url))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text(ByteCountFormatter.string(fromByteCount: record.bytes, countStyle: .file)).monospacedDigit()
                        backupBadge(record, status)
                        Text(record.verified.map { "Last check " + $0.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "en_US"))) } ?? "Integrity not checked")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    TextField("Add a note", text: $record.note)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Backup note")
                        .onSubmit { model.saveCatalog() }
                        .onChange(of: record.note) { _, _ in model.saveCatalog() }
                    backupActions(record, status)
                }.padding(.vertical, 12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func backupActions(_ record: BackupRecord, _ status: BackupAvailability) -> some View {
        HStack(spacing: 6) {
            if status == .available {
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([record.url]) }
                Button("Verify") { model.useBackup(record.url, restore: false) }
                Button("Restore…") { model.useBackup(record.url, restore: true) }
            } else {
                Button("Locate…") { model.locateBackup(record) }
            }
            Menu {
                Button("Locate moved backup…") { model.locateBackup(record) }
                Button("Remove from list…") { model.forgetBackup(record) }
            } label: { Image(systemName: "ellipsis").accessibilityLabel("Backup options") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
        }.buttonStyle(.action(small: true))
    }

    private func location(_ url: URL) -> String {
        let parts = url.pathComponents
        if parts.count > 2, parts[1] == "Volumes" { return "Disk “\(parts[2])”" }
        return "This Mac · " + url.deletingLastPathComponent().lastPathComponent
    }

    private func backupBadge(_ record: BackupRecord, _ status: BackupAvailability) -> some View {
        switch status {
        case .diskDisconnected: return Badge(text: "Disk not connected", color: Palette.warning)
        case .missing: return Badge(text: "File missing", color: Palette.danger)
        case .checking: return Badge(text: "Checking…", color: Palette.neutral)
        case .available: return Badge(text: "Available", color: Palette.accent)
        }
    }

    // MARK: Diagnostics

    private var diagnostics: some View {
        let failed = model.checks.filter { $0.severity == .failure || $0.severity == .warning }
        let passed = model.checks.filter(\.passed)
        let informational = model.checks.filter { $0.severity == .information }
        return VStack(alignment: .leading, spacing: 16) {
            if model.checks.isEmpty {
                Card {
                    Text("Not checked yet").font(.headline)
                    Text("Run checks inspects the app bundle, Wine engine, Windows prefix, .NET runtimes, the launcher and the game download, and lists running Outlands processes. It does not start the game.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Card {
                    HStack(spacing: 10) {
                        Text("\(passed.count) verified · \(informational.count) informational · \(failed.count) need attention").font(.system(size: 15, weight: .semibold))
                        if let time = model.lastCheck {
                            Text(time.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Text("Files and runtimes only. Gameplay is not tested.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(failed) { check in
                        checkRow(check)
                            .padding(.horizontal, 12).padding(.vertical, 2)
                            .background(Palette.warning.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.warning.opacity(0.25)))
                    }
                    ForEach(informational) { check in checkRow(check) }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 24), GridItem(.flexible())], alignment: .leading, spacing: 0) {
                        ForEach(passed) { checkRow($0) }
                    }
                }
            }
            Card {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Text("Wine processes for Outlands").font(.headline)
                            Text(model.hasProcessSnapshot ? "\(model.processes.filter { !$0.isBackgroundService }.count) applications · \(model.processes.filter(\.isBackgroundService).count) background services" : "Not checked yet")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if !model.processes.isEmpty {
                            DisclosureGroup("Show details", isExpanded: $showProcesses) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(model.processes) { process in
                                        Text("PID \(process.pid) · \(process.name)")
                                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                            }.font(.callout)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Close processes…", role: .destructive) { model.stopGame() }.buttonStyle(.action(.danger))
                }
            }
            HStack(alignment: .top) {
                if !model.externalLinks.isEmpty {
                    DisclosureGroup(model.externalLinks.count == 1 ? "1 folder linked from outside the app is not included in backups"
                                    : "\(model.externalLinks.count) folders linked from outside the app are not included in backups",
                                    isExpanded: $showLinks) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(model.externalLinks, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.font(.caption)
                }
                Spacer(minLength: 0)
                Button("Report a problem…") { model.prepareReport() }.buttonStyle(LinkButtonStyle())
            }
        }
    }

    private func checkRow(_ check: Diagnostic) -> some View {
        let color = check.passed ? Palette.accent : check.severity == .information ? Palette.neutral : Palette.warning
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.passed ? "checkmark.circle.fill" : check.severity == .information ? "info.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).fontWeight(.semibold)
                Text(check.detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text(check.passed ? "Verified" : check.severity == .information ? "Information" : "Needs attention").font(.caption.weight(.semibold)).foregroundStyle(color)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    // MARK: Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionLabel(text: "Updates")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ActionRow(title: "Check for updates automatically", detail: "Checks GitHub at most once a day. No logs are sent.") {
                        Toggle("Check for updates automatically", isOn: $model.automaticUpdates).labelsHidden().toggleStyle(.switch)
                    }
                    Divider()
                    ActionRow(title: "Version \(AppInfo.version) \(AppInfo.channel)",
                              detail: model.updateMessage.isEmpty ? "Not checked during this session." : model.updateMessage) {
                        HStack(spacing: 10) {
                            if let url = model.releaseURL {
                                Button("View update") { NSWorkspace.shared.open(url) }.buttonStyle(LinkButtonStyle())
                            }
                            Button(model.checkingUpdate ? "Checking…" : "Check now") { Task { await model.checkUpdates() } }
                                .buttonStyle(.action).disabled(model.checkingUpdate)
                        }
                    }
                }.padding(.horizontal, 20)
            }
            SectionLabel(text: "Appearance")
            Card(padding: 0) {
                ActionRow(title: "Theme", detail: "System follows your Mac's Light or Dark setting.") {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                }.padding(.horizontal, 20)
            }
            SectionLabel(text: "Privacy and safety")
            Card {
                fact("Backups are never deleted automatically.")
                fact("Problem reports open as a draft you review. Nothing is sent for you.")
                fact("Restored copies are never launched automatically.")
            }
            HStack(spacing: 12) {
                Text("Community project, not affiliated with Outlands. Icons by Game-icons.net artists, CC BY 3.0.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Artwork credits") { NSWorkspace.shared.open(URL(string: "https://game-icons.net/about.html#authors")!) }
                    .buttonStyle(LinkButtonStyle(small: true))
                Button("Bundled credits") {
                    if let url = GameArt.resource("CREDITS", extension: "txt") { NSWorkspace.shared.open(url) }
                }.buttonStyle(LinkButtonStyle(small: true))
            }
        }
    }

    private func fact(_ text: String) -> some View {
        Label { Text(text) } icon: { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
    }

    // MARK: Report

    private var backupPreviewSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review your backup").font(.title2.bold())
            Text(model.backupKind.title).font(.headline)
            if let preview = model.preview {
                Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 10) {
                    GridRow { Text("Files"); Text("\(preview.files)").monospacedDigit() }
                    GridRow { Text("Profile files"); Text("\(preview.profileFiles)") }
                    GridRow { Text("Scripts / macros"); Text("\(preview.scripts) / \(preview.macros)") }
                    GridRow { Text("Uncompressed data"); Text(ByteCountFormatter.string(fromByteCount: preview.bytes, countStyle: .file)) }
                    GridRow { Text("Links (target data excluded)"); Text("\(preview.externalLinks)") }
                }
                Text(model.backupKind == .settings ? "Includes ClassicUO and Razor settings, profiles, scripts and macros. Excludes game downloads, Wine, plugin binaries and journal logs." : "Includes the entire game application and Wine runtime. External linked data is excluded.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Close the game and Razor before saving. Contents may change after this preview; creation checks them again. The compressed size will be known after completion. Backups are local and unencrypted.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel") { model.showBackupPreview = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose destination…") { model.showBackupPreview = false; model.createBackup() }.keyboardShortcut(.defaultAction).buttonStyle(.action(.primary))
            }
        }.padding(24).frame(width: 550)
    }

    private var settingsImportSheet: some View {
        let files = model.importPlan?.files ?? []
        let filtered = files.filter { model.importSearch.isEmpty || $0.path.localizedCaseInsensitiveContains(model.importSearch) }
        let selected = files.filter { model.selectedSettings.contains($0.path) }
        return VStack(alignment: .leading, spacing: 14) {
            Text("Review settings to restore").font(.title2.bold())
            Text("Select the files to add or replace. Unselected files stay unchanged. Close Outlands before applying. The entire current ClassicUO directory is preserved for Undo; game assets and Wine remain in place.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Find profiles, scripts or settings", text: $model.importSearch).textFieldStyle(.roundedBorder)
                Button("All files") { model.selectedSettings = Set(files.map(\.path)) }.help("Select every file, including files hidden by search.")
                Button("Clear all") { model.selectedSettings = [] }
                Button("New files only") { model.selectedSettings = Set(files.filter { !$0.replacesExisting }.map(\.path)) }.help("Select new files across the entire recovery, including files hidden by search.")
            }
            Text("\(selected.count) selected · \(selected.filter(\.replacesExisting).count) existing files replaced").font(.callout.bold())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(filtered) { file in
                        Toggle(isOn: Binding(get: { model.selectedSettings.contains(file.path) }, set: { if $0 { model.selectedSettings.insert(file.path) } else { model.selectedSettings.remove(file.path) } })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path).font(.callout).textSelection(.enabled)
                                Text(file.replacesExisting ? "Replace existing file" : "Add new file").font(.caption).foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox).help(file.path)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 330)
            Text("Preparing and preserving ClassicUO needs additional space on the game disk. This can take longer than extracting the settings archive. Links are not imported automatically.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel") { model.showSettingsImport = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply selected files") { model.applySettings() }.keyboardShortcut(.return, modifiers: .command).buttonStyle(.action(.warning)).disabled(selected.isEmpty)
            }
        }.padding(24).frame(width: 700)
    }

    private var reportSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review your problem report").font(.title2.bold())
            Text("Continue opens a public GitHub issue draft. Nothing is posted until you submit it. Logs, backups and profiles are not attached.").foregroundStyle(.secondary)
            TextEditor(text: $model.report).font(.system(.body, design: .monospaced)).frame(minHeight: 300)
            HStack {
                Button("Cancel") { model.showReport = false }.buttonStyle(.action).keyboardShortcut(.cancelAction)
                Button("Copy report") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.report, forType: .string) }
                    .buttonStyle(.action)
                Spacer()
                Button("Continue to GitHub") { NSWorkspace.shared.open(ProblemReport.issueURL(body: model.report)) }
                    .buttonStyle(.action(.primary))
            }
        }.padding(28).frame(width: 680).background(Palette.window)
    }
}
