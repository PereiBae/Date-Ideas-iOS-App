import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        extractSharedURL()
    }

    private func extractSharedURL() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            complete()
            return
        }

        let providers = extensionItems
            .compactMap(\.attachments)
            .flatMap { $0 }

        if let urlProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
            urlProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
                if let url = item as? URL {
                    SharedImportQueue.enqueue(url)
                } else if let text = item as? String, let url = URL(string: text) {
                    SharedImportQueue.enqueue(url)
                }

                DispatchQueue.main.async {
                    self?.complete()
                }
            }
            return
        }

        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                if let text = item as? String {
                    text
                        .split(separator: " ")
                        .compactMap { URL(string: String($0)) }
                        .first
                        .map(SharedImportQueue.enqueue)
                }

                DispatchQueue.main.async {
                    self?.complete()
                }
            }
            return
        }

        complete()
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

