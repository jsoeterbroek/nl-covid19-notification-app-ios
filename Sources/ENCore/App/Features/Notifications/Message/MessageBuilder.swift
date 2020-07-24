/*
 * Copyright (c) 2020 De Staat der Nederlanden, Ministerie van Volksgezondheid, Welzijn en Sport.
 *  Licensed under the EUROPEAN UNION PUBLIC LICENCE v. 1.2
 *
 *  SPDX-License-Identifier: EUPL-1.2
 */

import ENFoundation
import Foundation

/// @mockable
protocol MessageListener: AnyObject {
    func messageWantsDismissal(shouldDismissViewController: Bool)
}

/// @mockable
protocol MessageBuildable {
    /// Builds Message
    ///
    /// - Parameter listener: Listener of created MessageViewController
    func build(withListener listener: MessageListener, title: String, body: String) -> ViewControllable
}

protocol MessageDependency {
    var theme: Theme { get }
}

private final class MessageDependencyProvider: DependencyProvider<MessageDependency> {}

final class MessageBuilder: Builder<MessageDependency>, MessageBuildable {
    func build(withListener listener: MessageListener, title: String, body: String) -> ViewControllable {
        let dependencyProvider = MessageDependencyProvider(dependency: dependency)
        return MessageViewController(listener: listener,
                                     theme: dependencyProvider.dependency.theme,
                                     message: MessageViewController.Message(title: title, body: body))
    }
}
