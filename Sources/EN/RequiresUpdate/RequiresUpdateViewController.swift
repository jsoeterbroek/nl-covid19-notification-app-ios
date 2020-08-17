/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import ENFoundation
import Foundation
import UIKit

final class RequiresUpdateViewController: UIViewController {

    // MARK: - Lifecycle

    init(deviceModel: String, theme: Theme) {
        isDeviceSupported = RequiresUpdateViewController.unsupportedDevicesModels.contains(deviceModel) == false
        self.theme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupViews()
        setupConstraints()
    }

    // MARK: - Setups

    private func setupViews() {

        self.view = internalView
        self.view.frame = UIScreen.main.bounds
        self.view.backgroundColor = theme.colors.viewControllerBackground

        self.view.addSubview(button)

        button.isHidden = isDeviceSupported == false

        let titleKey = isDeviceSupported ? "update.software.os.title" : "update.hardware.title"
        internalView.titleLabel.text = localizedString(for: titleKey)
        internalView.titleLabel.font = theme.fonts.title2

        let descriptionKey = isDeviceSupported ? "update.software.os.description" : "update.hardware.description"
        internalView.contentLabel.text = localizedString(for: descriptionKey)
        internalView.contentLabel.font = theme.fonts.body
    }

    private func setupConstraints() {

        var constraints = [[NSLayoutConstraint]()]

        constraints.append([
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -50),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            button.heightAnchor.constraint(equalToConstant: 50)
        ])

        for constraint in constraints { NSLayoutConstraint.activate(constraint) }
    }

    // MARK: - Functions

    @objc func buttonPressed() {
        present(UpdateInstructionsViewController(theme: theme), animated: true, completion: nil)
    }

    // MARK: - Private

    private let theme: Theme
    private let isDeviceSupported: Bool

    private lazy var internalView: RequiresUpdateView = RequiresUpdateView()

    private lazy var button: UIButton = {
        let button = UIButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(localizedString(for: "update.button.update"), for: .normal)
        button.titleLabel?.font = theme.fonts.bodyBold
        button.layer.cornerRadius = 10
        button.clipsToBounds = true
        button.backgroundColor = theme.colors.primary
        button.setTitleColor(.white, for: .normal)
        button.addTarget(self, action: #selector(buttonPressed), for: .touchUpInside)
        return button
    }()

    // Only devices that support iOS 11 and not iOS 13.
    private static let unsupportedDevicesModels = [
        "iPhone6,1", // iPhone 5s
        "iPhone6,2", // iPhone 5s
        "iPhone7,2", // iPhone 6
        "iPhone7,1" // iPhone 6 Plus
    ]
}

final class RequiresUpdateView: UIView {

    private lazy var imageView: UIImageView = {
        let imageView = UIImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.image = UIImage(named: "SoftwareUpdate")
        return imageView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()

    lazy var contentLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.numberOfLines = 0
        return label
    }()

    private lazy var viewsInDisplayOrder = [imageView, titleLabel, contentLabel]

    // MARK: - Live cycle

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupViews()
        setupConstraints()
    }

    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)

        setupViews()
        setupConstraints()
    }

    private func setupViews() {

        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .white
        viewsInDisplayOrder.forEach { addSubview($0) }
    }

    private func setupConstraints() {

        var constraints = [[NSLayoutConstraint]()]

        constraints.append([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 75),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: 0.83, constant: 1)
        ])

        constraints.append([
            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 40),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            titleLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        constraints.append([
            contentLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            contentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            contentLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            contentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])

        constraints.forEach { NSLayoutConstraint.activate($0) }

        self.contentLabel.sizeToFit()
    }
}
