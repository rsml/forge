import SwiftUI
import UniformTypeIdentifiers

struct ReorderDropDelegate<Item: Identifiable>: DropDelegate where Item.ID == String {
    let item: Item
    var items: [Item]
    @Binding var draggedItemId: String?
    var onMove: (IndexSet, Int) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedId = draggedItemId,
              draggedId != item.id,
              let from = items.firstIndex(where: { $0.id == draggedId }),
              let to = items.firstIndex(where: { $0.id == item.id }),
              from != to
        else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 1.0)) {
            let dest = from < to ? to + 1 : to
            onMove(IndexSet(integer: from), dest)
        }
    }

    func dropExited(info: DropInfo) {
        // Don't clear here — let performDrop handle cleanup
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedItemId = nil
        return true
    }
}
