import Foundation

public struct SessionSnapshot: Codable {
    public let path: String
    public let savedAt: Date
    public let tabs: [TabSnapshot]

    public init(path: String, savedAt: Date = Date(), tabs: [TabSnapshot]) {
        self.path = path
        self.savedAt = savedAt
        self.tabs = tabs
    }
}

public struct TabSnapshot: Codable {
    public let name: String
    public let index: Int
    public let layout: String?
    public let panes: [PaneSnapshot]

    public init(name: String, index: Int, layout: String?, panes: [PaneSnapshot]) {
        self.name = name
        self.index = index
        self.layout = layout
        self.panes = panes
    }
}

public struct PaneSnapshot: Codable {
    public let directory: String
    public let index: Int

    public init(directory: String, index: Int) {
        self.directory = directory
        self.index = index
    }
}
