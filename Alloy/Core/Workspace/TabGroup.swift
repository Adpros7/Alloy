import Foundation

/// A group of editor tabs. Phase 1 has one tab group; Phase 5 adds split views.
@MainActor
final class TabGroup: ObservableObject {

    @Published private(set) var tabs: [DocumentID] = []
    @Published private(set) var activeIndex: Int = -1

    var activeDocumentID: DocumentID? {
        guard activeIndex >= 0 && activeIndex < tabs.count else { return nil }
        return tabs[activeIndex]
    }

    func open(_ id: DocumentID) {
        if let existing = tabs.firstIndex(of: id) {
            activeIndex = existing
        } else {
            tabs.append(id)
            activeIndex = tabs.count - 1
        }
    }

    func close(_ id: DocumentID) {
        guard let idx = tabs.firstIndex(of: id) else { return }
        tabs.remove(at: idx)
        if tabs.isEmpty {
            activeIndex = -1
        } else {
            activeIndex = max(0, min(activeIndex, tabs.count - 1))
        }
    }

    func activate(_ id: DocumentID) {
        if let idx = tabs.firstIndex(of: id) {
            activeIndex = idx
        }
    }

    func moveTab(from sourceOffsets: IndexSet, to destination: Int) {
        // Manual move without SwiftUI dependency.
        var result = tabs
        let items = sourceOffsets.map { result[$0] }
        for idx in sourceOffsets.reversed() { result.remove(at: idx) }
        let insertAt = min(destination, result.count)
        result.insert(contentsOf: items, at: insertAt)
        tabs = result
        if let activeID = activeDocumentID,
           let newIdx = tabs.firstIndex(of: activeID) {
            activeIndex = newIdx
        }
    }
}
