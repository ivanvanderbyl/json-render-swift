import JSONRender
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Host callbacks for the standard actions, like the options of upstream
/// `createStandardActionHandlers`. An action whose callback is nil does
/// nothing.
public struct StandardActionOptions {
    /// `navigate`: the screen name and its optional params.
    public var navigate: (@MainActor (_ screen: String, _ params: JSONObject?) -> Void)?
    /// `goBack`.
    public var goBack: (@MainActor () -> Void)?
    /// `setData`: the state path and value.
    public var onSetData: (@MainActor (_ statePath: String, _ value: JSONValue) -> Void)?
    /// `refresh`: the optional target.
    public var onRefresh: (@MainActor (_ target: String?) -> Void)?

    public init(
        navigate: (@MainActor (_ screen: String, _ params: JSONObject?) -> Void)? = nil,
        goBack: (@MainActor () -> Void)? = nil,
        onSetData: (@MainActor (_ statePath: String, _ value: JSONValue) -> Void)? = nil,
        onRefresh: (@MainActor (_ target: String?) -> Void)? = nil
    ) {
        self.navigate = navigate
        self.goBack = goBack
        self.onSetData = onSetData
        self.onRefresh = onRefresh
    }
}

/// An alert for `showAlert`, like React Native `Alert.alert(title, message, buttons)`.
public struct AlertRequest: Sendable, Equatable {
    public struct Button: Sendable, Equatable {
        public var text: String
        /// "default", "cancel" or "destructive".
        public var style: String?
    }

    public var title: String
    public var message: String?
    public var buttons: [Button]?
}

/// Content for `share`, like React Native `Share.share({ message, url, title })`.
public struct ShareRequest: Sendable, Equatable {
    public var message: String
    public var url: String?
    public var title: String?
}

/// The system features the standard actions use, standing in for React
/// Native's `Alert`, `Share` and `Linking`. ``live`` uses UIKit or AppKit.
public struct SystemServices {
    public var alert: @MainActor (AlertRequest) -> Void
    public var share: @MainActor (ShareRequest) async throws -> Void
    public var canOpenURL: @MainActor (String) async -> Bool
    public var openURL: @MainActor (String) async throws -> Void

    public init(
        alert: @escaping @MainActor (AlertRequest) -> Void,
        share: @escaping @MainActor (ShareRequest) async throws -> Void,
        canOpenURL: @escaping @MainActor (String) async -> Bool,
        openURL: @escaping @MainActor (String) async throws -> Void
    ) {
        self.alert = alert
        self.share = share
        self.canOpenURL = canOpenURL
        self.openURL = openURL
    }
}

/// Handlers for the standard actions, like upstream
/// `createStandardActionHandlers`: navigate, goBack, showAlert, share,
/// openURL, setData and refresh. `setState`, `pushState` and `removeState`
/// are built into the runtime.
public enum StandardActions {
    @MainActor
    public static func handlers(_ options: StandardActionOptions = StandardActionOptions(), services: SystemServices? = nil) -> [String: ActionHandler] {
        let services = services ?? .live
        func text(_ value: JSONValue?) -> String? {
            guard let value, !value.isNullish else { return nil }
            return value.javaScriptString
        }
        return [
            "navigate": { params in
                options.navigate?(text(params["screen"]) ?? "", params["params"]?.objectValue)
                return .undefined
            },
            "goBack": { _ in
                options.goBack?()
                return .undefined
            },
            "showAlert": { params in
                let buttons = params["buttons"]?.arrayValue.map { items in
                    items.map { AlertRequest.Button(text: text($0["text"]) ?? "", style: text($0["style"])) }
                }
                services.alert(AlertRequest(title: text(params["title"]) ?? "", message: text(params["message"]), buttons: buttons))
                return .undefined
            },
            "share": { params in
                try await services.share(ShareRequest(message: text(params["message"]) ?? "", url: text(params["url"]), title: text(params["title"])))
                return .undefined
            },
            "openURL": { params in
                let url = text(params["url"]) ?? ""
                if await services.canOpenURL(url) {
                    try await services.openURL(url)
                }
                return .undefined
            },
            "setData": { params in
                options.onSetData?(text(params["statePath"]) ?? "", params["value"] ?? .undefined)
                return .undefined
            },
            "refresh": { params in
                options.onRefresh?(text(params["target"]))
                return .undefined
            },
        ]
    }
}

extension SystemServices {
    /// Alerts, sharing and URL opening with UIKit on iOS and AppKit on macOS.
    @MainActor
    public static var live: SystemServices {
        SystemServices(
            alert: { request in SystemPresenter.alert(request) },
            share: { request in await SystemPresenter.share(request) },
            canOpenURL: { url in SystemPresenter.canOpen(url) },
            openURL: { url in await SystemPresenter.open(url) }
        )
    }
}

@MainActor
enum SystemPresenter {
    #if canImport(UIKit)
    static var topController: UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }

    static func alert(_ request: AlertRequest) {
        let alert = UIAlertController(title: request.title, message: request.message, preferredStyle: .alert)
        for button in request.buttons ?? [AlertRequest.Button(text: "OK", style: nil)] {
            let style: UIAlertAction.Style = switch button.style {
            case "cancel": .cancel
            case "destructive": .destructive
            default: .default
            }
            alert.addAction(UIAlertAction(title: button.text, style: style))
        }
        topController?.present(alert, animated: true)
    }

    static func share(_ request: ShareRequest) async {
        var items: [Any] = [request.message]
        if let url = request.url.flatMap(URL.init(string:)) { items.append(url) }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let top = topController else { return }
        controller.popoverPresentationController?.sourceView = top.view
        await withCheckedContinuation { continuation in
            controller.completionWithItemsHandler = { _, _, _, _ in continuation.resume() }
            top.present(controller, animated: true)
        }
    }

    static func canOpen(_ url: String) -> Bool {
        URL(string: url).map { UIApplication.shared.canOpenURL($0) } ?? false
    }

    static func open(_ url: String) async {
        guard let url = URL(string: url) else { return }
        await UIApplication.shared.open(url)
    }
    #elseif canImport(AppKit)
    static func alert(_ request: AlertRequest) {
        let alert = NSAlert()
        alert.messageText = request.title
        alert.informativeText = request.message ?? ""
        for button in request.buttons ?? [AlertRequest.Button(text: "OK", style: nil)] {
            let added = alert.addButton(withTitle: button.text)
            added.hasDestructiveAction = button.style == "destructive"
        }
        if let window = NSApplication.shared.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }

    static func share(_ request: ShareRequest) async {
        var items: [Any] = [request.message]
        if let url = request.url.flatMap(URL.init(string:)) { items.append(url) }
        guard let view = NSApplication.shared.keyWindow?.contentView else { return }
        NSSharingServicePicker(items: items).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }

    static func canOpen(_ url: String) -> Bool {
        URL(string: url).flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) } != nil
    }

    static func open(_ url: String) async {
        guard let url = URL(string: url) else { return }
        NSWorkspace.shared.open(url)
    }
    #endif
}
