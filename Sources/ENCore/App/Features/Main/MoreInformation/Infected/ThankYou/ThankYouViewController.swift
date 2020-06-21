/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import Foundation
import SnapKit
import UIKit

/// @mockable
protocol ThankYouViewControllable: ViewControllable {}

final class ThankYouViewController: ViewController, ThankYouViewControllable, UIAdaptivePresentationControllerDelegate {

    // MARK: - Init

    init(listener: ThankYouListener, theme: Theme, exposureConfirmationKey: ExposureConfirmationKey) {
        self.listener = listener
        self.exposureConfirmationKey = exposureConfirmationKey

        super.init(theme: theme)
    }

    // MARK: - Overrides

    override func loadView() {
        self.view = internalView
        self.view.frame = UIScreen.main.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Bedankt"
        navigationItem.hidesBackButton = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close,
                                                            target: self,
                                                            action: #selector(didTapCloseButton(sender:)))

        internalView.infoView.actionHandler = { [weak self] in
            self?.listener?.thankYouWantsDismissal()
        }
    }

    // MARK: - UIAdaptivePresentationControllerDelegate

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        listener?.thankYouWantsDismissal()
    }

    // MARK: - Private

    private weak var listener: ThankYouListener?
    private lazy var internalView: ThankYouView = ThankYouView(theme: self.theme, exposureConfirmationKey: exposureConfirmationKey)
    private let exposureConfirmationKey: ExposureConfirmationKey

    @objc private func didTapCloseButton(sender: UIBarButtonItem) {
        listener?.thankYouWantsDismissal()
    }
}

private final class ThankYouView: View {

    fileprivate let infoView: InfoView
    private let exposureConfirmationKey: ExposureConfirmationKey

    // MARK: - Init

    // TODO: Remove exposureConfirmationKey from init and make it settable
    init(theme: Theme, exposureConfirmationKey: ExposureConfirmationKey) {
        let config = InfoViewConfig(actionButtonTitle: "Sluiten",
                                    headerImage: Image.named("ThankYouHeader"))
        self.infoView = InfoView(theme: theme, config: config)
        self.exposureConfirmationKey = exposureConfirmationKey
        super.init(theme: theme)
    }

    // MARK: - Overrides

    override func build() {
        super.build()

        let bulletPoints = [
            "Blijf binnen tot 2 dagen na laatste   klachten",
            "Voorkom contact met je huisgenoten",
            "Worden je klachten erger? Neem direct contact op met de GGD of je huisarts"
        ]

        let header = NSAttributedString(string: "Je hebt geholpen de verspreiding van het coronavirus te stoppen. Bedankt en veel sterkte met je verdere herstel.")
        let list = NSAttributedString.bulletList(bulletPoints,
                                                 theme: theme,
                                                 font: theme.fonts.body)

        let footer = NSAttributedString(string: "Gebruikte controlecode: \(exposureConfirmationKey.key)")

        let string = NSMutableAttributedString()
        string.append(header)
        string.append(NSAttributedString(string: "\n\n"))
        string.append(list)
        string.append(NSAttributedString(string: "\n"))
        string.append(footer)

        let view = InfoSectionTextView(theme: theme,
                                       title: "Bedankt en beterschap",
                                       content: string)

        infoView.addSections([view])

        addSubview(infoView)
    }

    override func setupConstraints() {
        super.setupConstraints()

        infoView.snp.makeConstraints { (maker: ConstraintMaker) in
            maker.edges.equalToSuperview()
        }
    }
}
