import SwiftUI
import ForgeCore

struct ForgeMenuCommands: Commands {
    let controller: WorkspaceController
    let config: ForgeConfigStore
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Forge") {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                let alert = NSAlert()
                alert.messageText = "Forge \(version) (\(build))"
                alert.informativeText = "A native macOS frontend for tmux."
                alert.alertStyle = .informational
                if let iconPath = bundleResource("appicon-transparent.png"),
                   let icon = NSImage(contentsOf: iconPath) {
                    icon.size = NSSize(width: 128, height: 128)
                    alert.icon = icon
                }
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "View on GitHub")
                if alert.runModal() == .alertSecondButtonReturn {
                    NSWorkspace.shared.open(URL(string: "https://github.com/rsml/forge")!)
                }
            }
        }

        CommandGroup(replacing: .systemServices) { }

        // MARK: File
        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                appState.dispatch(.showProjectPicker)
            }
            .keyboardShortcut(KeyboardShortcuts.newProject.key, modifiers: KeyboardShortcuts.newProject.modifiers)

            Button("New Tab") {
                if config.isStackMode {
                    appState.dispatch(.showStackNewTab)
                } else if let project = controller.workspace.activeProject {
                    controller.addTab(in: project)
                }
            }
            .keyboardShortcut(KeyboardShortcuts.newTab.key, modifiers: KeyboardShortcuts.newTab.modifiers)

            Divider()

            Button("Close Pane") {
                if let keyWindow = NSApp.keyWindow,
                   keyWindow.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" {
                    keyWindow.close()
                    return
                }
                controller.closeCurrentPane()
            }
            .keyboardShortcut(KeyboardShortcuts.closePane.key, modifiers: KeyboardShortcuts.closePane.modifiers)

            Button("Close Project") {
                guard let project = controller.workspace.activeProject else { return }
                let alert = NSAlert()
                alert.messageText = "Close project \"\(project.name)\"?"
                alert.informativeText = "This will close all tabs and remove the project from Forge."
                alert.addButton(withTitle: "Close Project")
                alert.addButton(withTitle: "Cancel")
                alert.alertStyle = .warning
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                Task { await controller.removeProject(project) }
            }
            .keyboardShortcut(KeyboardShortcuts.closeProject.key, modifiers: KeyboardShortcuts.closeProject.modifiers)

            Divider()

            Button("Rename Tab...") {
                appState.dispatch(.renameTab)
            }
            .keyboardShortcut(KeyboardShortcuts.renameTab.key, modifiers: KeyboardShortcuts.renameTab.modifiers)

            Button("Rename Project...") {
                appState.dispatch(.renameProject)
            }
            .keyboardShortcut(KeyboardShortcuts.renameProject.key, modifiers: KeyboardShortcuts.renameProject.modifiers)
        }

        // MARK: Edit
        CommandGroup(replacing: .pasteboard) {
            Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            Divider()
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x", modifiers: .command)
            Button("Copy") { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
                .keyboardShortcut("c", modifiers: .command)
            Button("Paste") { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                .keyboardShortcut("v", modifiers: .command)
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a", modifiers: .command)
        }

        // MARK: View
        CommandMenu("View") {
            Button("Tab Switcher") {
                appState.dispatch(.showTabSwitcher)
            }
            .keyboardShortcut(KeyboardShortcuts.tabSwitcher.key, modifiers: KeyboardShortcuts.tabSwitcher.modifiers)

            Button("Command Palette") {
                appState.dispatch(.showCommandPalette)
            }
            .keyboardShortcut(KeyboardShortcuts.commandPalette.key, modifiers: KeyboardShortcuts.commandPalette.modifiers)

            Divider()

            Button("Toggle Sidebar") {
                appState.dispatch(.toggleSidebar)
            }
            .keyboardShortcut(KeyboardShortcuts.toggleSidebar.key, modifiers: KeyboardShortcuts.toggleSidebar.modifiers)

            Button("Notifications") {
                appState.dispatch(.showNotifications)
            }
            .keyboardShortcut(KeyboardShortcuts.notifications.key, modifiers: KeyboardShortcuts.notifications.modifiers)

            Button("Toggle Mode") {
                appState.dispatch(.toggleMode)
            }
            .keyboardShortcut(KeyboardShortcuts.toggleMode.key, modifiers: KeyboardShortcuts.toggleMode.modifiers)

            Divider()

            Button("Split Horizontally") {
                controller.splitPane(direction: .horizontal)
            }
            .keyboardShortcut(KeyboardShortcuts.splitHorizontal.key, modifiers: KeyboardShortcuts.splitHorizontal.modifiers)

            Button("Split Vertically") {
                controller.splitPane(direction: .vertical)
            }
            .keyboardShortcut(KeyboardShortcuts.splitVertical.key, modifiers: KeyboardShortcuts.splitVertical.modifiers)

            Divider()

            Button("Clear Scrollback") {
                controller.clearScrollback()
            }
            .keyboardShortcut(KeyboardShortcuts.clearScrollback.key, modifiers: KeyboardShortcuts.clearScrollback.modifiers)
        }

        // MARK: Tab
        CommandMenu("Tab") {
            Menu("Switch to Tab") {
                ForEach(1...9, id: \.self) { n in
                    Button("Tab \(n)") {
                        guard let project = controller.workspace.activeProject,
                              project.tabs.count >= n
                        else { return }
                        controller.selectTab(project.tabs[n - 1])
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                }
            }

            Menu("Switch to Project") {
                ForEach(Array(controller.workspace.projects.enumerated().prefix(9)), id: \.element.id) { index, project in
                    Button(project.name) {
                        controller.selectProject(project)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .option)
                }
            }

            Divider()

            Button("Previous Tab") {
                guard let project = controller.workspace.activeProject,
                      let tabId = controller.workspace.activeTabId,
                      let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                      idx > 0
                else { return }
                controller.selectTab(project.tabs[idx - 1])
            }
            .keyboardShortcut(KeyboardShortcuts.selectTabLeft.key, modifiers: KeyboardShortcuts.selectTabLeft.modifiers)

            if !config.isStackMode {
                Button("Next Tab") {
                    guard let project = controller.workspace.activeProject,
                          let tabId = controller.workspace.activeTabId,
                          let idx = project.tabs.firstIndex(where: { $0.id == tabId }),
                          idx < project.tabs.count - 1
                    else { return }
                    controller.selectTab(project.tabs[idx + 1])
                }
                .keyboardShortcut(KeyboardShortcuts.selectTabRight.key, modifiers: KeyboardShortcuts.selectTabRight.modifiers)
            }

            if config.isStackMode {
                Divider()
                Button("Done") {
                    appState.dispatch(.stackDone)
                }
                .keyboardShortcut(KeyboardShortcuts.stackDone.key, modifiers: KeyboardShortcuts.stackDone.modifiers)

                Button("Disable Notifications") {
                    appState.dispatch(.stackHide)
                }
                .keyboardShortcut(KeyboardShortcuts.stackHide.key, modifiers: KeyboardShortcuts.stackHide.modifiers)

                Button("Move to Back") {
                    appState.dispatch(.stackMoveToBack)
                }
                .keyboardShortcut(KeyboardShortcuts.stackMoveToBack.key, modifiers: KeyboardShortcuts.stackMoveToBack.modifiers)
            }

            if !config.isStackMode {
                Divider()
                Button("Toggle Notifications") {
                    appState.dispatch(.toggleNotifications)
                }
                .keyboardShortcut(KeyboardShortcuts.toggleNotifications.key, modifiers: KeyboardShortcuts.toggleNotifications.modifiers)
            }

            Button("Move Tab Back") {
                appState.dispatch(.moveTabLeft)
            }
            .keyboardShortcut(KeyboardShortcuts.moveTabLeft.key, modifiers: KeyboardShortcuts.moveTabLeft.modifiers)

            Button("Move Tab Forward") {
                appState.dispatch(.moveTabRight)
            }
            .keyboardShortcut(KeyboardShortcuts.moveTabRight.key, modifiers: KeyboardShortcuts.moveTabRight.modifiers)

            Divider()

            Button("Next Project") {
                let sessions = controller.workspace.projects
                guard sessions.count > 1,
                      let activeId = controller.workspace.activeProjectId,
                      let idx = sessions.firstIndex(where: { $0.id == activeId })
                else { return }
                let next = sessions[(idx + 1) % sessions.count]
                controller.selectProject(next)
            }
            .keyboardShortcut(KeyboardShortcuts.nextProject.key, modifiers: KeyboardShortcuts.nextProject.modifiers)

            Button("Move Project Back") {
                appState.dispatch(.moveProjectBack)
            }
            .keyboardShortcut(KeyboardShortcuts.moveProjectBack.key, modifiers: KeyboardShortcuts.moveProjectBack.modifiers)

            Button("Move Project Forward") {
                appState.dispatch(.moveProjectForward)
            }
            .keyboardShortcut(KeyboardShortcuts.moveProjectForward.key, modifiers: KeyboardShortcuts.moveProjectForward.modifiers)

            Button("Previous Project") {
                let sessions = controller.workspace.projects
                guard sessions.count > 1,
                      let activeId = controller.workspace.activeProjectId,
                      let idx = sessions.firstIndex(where: { $0.id == activeId })
                else { return }
                let prev = sessions[(idx - 1 + sessions.count) % sessions.count]
                controller.selectProject(prev)
            }
            .keyboardShortcut(KeyboardShortcuts.prevProject.key, modifiers: KeyboardShortcuts.prevProject.modifiers)
        }

        // MARK: Help
        CommandMenu("Help") {
            Button("Forge Help") {
                NSApp.showHelp(nil)
            }
        }
    }
}
