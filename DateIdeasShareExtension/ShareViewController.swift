import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
    }

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
                var saved = false
                if let url = item as? URL {
                    SharedImportQueue.enqueue(url)
                    saved = true
                } else if let text = item as? String, let url = URL(string: text) {
                    SharedImportQueue.enqueue(url)
                    saved = true
                }

                DispatchQueue.main.async {
                    saved ? self?.showConfirmationThenComplete() : self?.complete()
                }
            }
            return
        }

        if let textProvider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) {
            textProvider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                var saved = false
                if let text = item as? String,
                   let url = text.split(separator: " ").compactMap({ URL(string: String($0)) }).first {
                    SharedImportQueue.enqueue(url)
                    saved = true
                }

                DispatchQueue.main.async {
                    saved ? self?.showConfirmationThenComplete() : self?.complete()
                }
            }
            return
        }

        complete()
    }

    // MARK: Confirmation card

    // A brief "Imported!" moment instead of the blank sheet flashing away.
    private func showConfirmationThenComplete() {
        let dim = UIView(frame: view.bounds)
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        dim.alpha = 0
        view.addSubview(dim)

        let card = makeCard()
        view.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 250)
        ])

        card.alpha = 0
        card.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)

        UINotificationFeedbackGenerator().notificationOccurred(.success)

        UIView.animate(
            withDuration: 0.45,
            delay: 0,
            usingSpringWithDamping: 0.7,
            initialSpringVelocity: 0.6
        ) {
            dim.alpha = 1
            card.alpha = 1
            card.transform = .identity
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            UIView.animate(withDuration: 0.2) {
                dim.alpha = 0
                card.alpha = 0
                card.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
            } completion: { _ in
                self?.complete()
            }
        }
    }

    private func makeCard() -> UIView {
        let accent = UIColor(red: 0xF2 / 255, green: 0x6B / 255, blue: 0x1D / 255, alpha: 1)

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0x26 / 255, green: 0x21 / 255, blue: 0x1D / 255, alpha: 1)
                : .white
        }
        card.layer.cornerRadius = 22
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 20
        card.layer.shadowOffset = CGSize(width: 0, height: 10)

        let circle = UIView()
        circle.translatesAutoresizingMaskIntoConstraints = false
        circle.backgroundColor = accent
        circle.layer.cornerRadius = 28

        let check = UIImageView(image: UIImage(
            systemName: "checkmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        ))
        check.translatesAutoresizingMaskIntoConstraints = false
        check.tintColor = .white
        circle.addSubview(check)

        let title = UILabel()
        title.text = "Imported!"
        title.font = .systemFont(ofSize: 18, weight: .bold)
        title.textColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0xF0 / 255, green: 0xE7 / 255, blue: 0xE1 / 255, alpha: 1)
                : UIColor(red: 0x2B / 255, green: 0x24 / 255, blue: 0x20 / 255, alpha: 1)
        }

        let subtitle = UILabel()
        subtitle.text = "Review it in RendezQueue"
        subtitle.font = .systemFont(ofSize: 13, weight: .medium)
        subtitle.textColor = UIColor(red: 0x8A / 255, green: 0x7F / 255, blue: 0x76 / 255, alpha: 1)

        let stack = UIStackView(arrangedSubviews: [circle, title, subtitle])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 8
        stack.setCustomSpacing(14, after: circle)
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: 56),
            circle.heightAnchor.constraint(equalToConstant: 56),
            check.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20)
        ])

        return card
    }

    private func complete() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
