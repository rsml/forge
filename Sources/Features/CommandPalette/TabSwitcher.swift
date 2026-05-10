import SwiftUI
import ForgeCore

struct TabSwitcher: View {
    @Environment(WorkspaceController.self) var controller
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selectedIndex = 0
    @State private var useMouseSelection = true
    @FocusState private var isFieldFocused: Bool

    private var results: [SwitcherItem] {
        let workspace = controller.workspace
        var items: [SwitcherItem] = []
        for project in workspace.projects {
            if matches(project.name) {
                items.append(SwitcherItem(title: project.name, context: nil, action: { [weak controller] in
                    controller?.selectProject(project)
                }))
            }
            for tab in project.tabs {
                if matches(tab.name) || matches(project.name) {
                    items.append(SwitcherItem(title: tab.name, context: project.name, action: { [weak controller] in
                        controller?.selectProject(project)
                        controller?.selectTab(tab)
                    }))
                }
            }
        }
        return items
    }

    private func matches(_ text: String) -> Bool {
        query.isEmpty || text.lowercased().contains(query.lowercased())
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Switch to project or tab...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($isFieldFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .onSubmit { executeSelected() }
                .onChange(of: query) {
                    selectedIndex = 0
                    useMouseSelection = false
                }

            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { index, item in
                                HStack {
                                    Text(item.title)
                                        .font(.system(size: 13))
                                    Spacer()
                                    if let context = item.context {
                                        Text(context)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                                .contentShape(Rectangle())
                                .id(index)
                                .onHover { hovering in
                                    if hovering {
                                        useMouseSelection = true
                                        selectedIndex = index
                                    }
                                }
                                .onTapGesture {
                                    selectedIndex = index
                                    executeSelected()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                    .onChange(of: selectedIndex) { _, newValue in
                        if !useMouseSelection {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFieldFocused = true
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.upArrow) {
            useMouseSelection = false
            selectedIndex = max(0, selectedIndex - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            useMouseSelection = false
            selectedIndex = min(results.count - 1, selectedIndex + 1)
            return .handled
        }
    }

    private func executeSelected() {
        guard selectedIndex < results.count else { return }
        let item = results[selectedIndex]
        dismiss()
        item.action()
    }

    private func dismiss() {
        isPresented = false
        query = ""
        selectedIndex = 0
    }
}

struct SwitcherItem {
    let title: String
    let context: String?
    let action: () -> Void
}
