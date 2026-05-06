import SwiftUI
import ForgeDomain

struct TerminalArea: View {
    var project: Project

    var body: some View {
        // Key only on project so terminal recreates when switching projects, but NOT
        // when switching tabs — tmux handles tab switching internally via select-window,
        // so there's no need to recreate the terminal view (which causes a blank flash).
        ForgeTerminalView(sessionName: project.name)
            .padding(.trailing, -15) // Compensate for SwiftTerm's reserved legacy scroller width
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: [.bottom, .trailing])
            .id(project.id)
            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
    }
}
