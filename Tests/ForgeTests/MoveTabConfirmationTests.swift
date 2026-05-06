import Testing
@testable import ForgeCore

@Suite("MoveTabConfirmation")
struct MoveTabConfirmationTests {

    @Test("returns nil when warnOnMoveTab is false")
    func noWarning() {
        let result = MoveTabConfirmation.evaluate(
            tabName: "vim", sourceProjectName: "alpha",
            targetProjectName: "beta", warnOnMoveTab: false
        )
        #expect(result == nil)
    }

    @Test("returns alert info when warnOnMoveTab is true")
    func showsWarning() {
        let result = MoveTabConfirmation.evaluate(
            tabName: "vim", sourceProjectName: "alpha",
            targetProjectName: "beta", warnOnMoveTab: true
        )
        #expect(result != nil)
        #expect(result?.message == "Move tab to \"beta\"?")
        #expect(result?.info == "\"vim\" will be moved from \"alpha\".")
        #expect(result?.action == "Move Tab")
        #expect(result?.suppressionLabel == "Don't ask again")
    }

    @Test("alert message includes target project name")
    func targetNameInMessage() {
        let result = MoveTabConfirmation.evaluate(
            tabName: "zsh", sourceProjectName: "src",
            targetProjectName: "My Cool Project", warnOnMoveTab: true
        )
        #expect(result?.message.contains("My Cool Project") == true)
    }

    @Test("alert info includes source project name")
    func sourceNameInInfo() {
        let result = MoveTabConfirmation.evaluate(
            tabName: "zsh", sourceProjectName: "source-proj",
            targetProjectName: "dest", warnOnMoveTab: true
        )
        #expect(result?.info.contains("source-proj") == true)
    }

    @Test("alert info includes tab name")
    func tabNameInInfo() {
        let result = MoveTabConfirmation.evaluate(
            tabName: "my-editor", sourceProjectName: "a",
            targetProjectName: "b", warnOnMoveTab: true
        )
        #expect(result?.info.contains("my-editor") == true)
    }
}
