import Foundation

@MainActor
public protocol GitPort {
    func currentBranch(at path: String) async -> String?
}
