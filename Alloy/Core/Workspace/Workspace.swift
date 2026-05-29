import Foundation

/// The workspace owns all open documents and the tab group.
/// It is the central model object passed down to all UI components.
@MainActor
final class Workspace: ObservableObject {

    @Published private(set) var documents: [DocumentID: Document] = [:]
    let tabGroup = TabGroup()

    // MARK: - Document management

    @discardableResult
    func newUntitledDocument() -> Document {
        let doc = Document()
        documents[doc.id] = doc
        tabGroup.open(doc.id)
        return doc
    }

    @discardableResult
    func openDocument(at url: URL) throws -> Document {
        // Re-activate if already open.
        if let existing = documents.values.first(where: { $0.fileURL == url }) {
            tabGroup.activate(existing.id)
            return existing
        }
        let doc = try Document.open(url: url)
        documents[doc.id] = doc
        tabGroup.open(doc.id)
        return doc
    }

    func closeDocument(_ id: DocumentID) {
        tabGroup.close(id)
        documents.removeValue(forKey: id)
    }

    var activeDocument: Document? {
        guard let id = tabGroup.activeDocumentID else { return nil }
        return documents[id]
    }
}
