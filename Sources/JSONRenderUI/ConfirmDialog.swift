import JSONRender
import SwiftUI

/// The text of a confirmation dialog, like upstream `ConfirmDialog`: the
/// action's `confirm` title and message, with "Confirm" and "Cancel" as the
/// default button labels and a destructive confirm button for the "danger"
/// variant.
public struct ConfirmDialogContent: Equatable {
    public var title: String
    public var message: String
    public var confirmLabel: String
    public var cancelLabel: String
    public var isDestructive: Bool

    public init(_ confirm: JSONValue) {
        func text(_ key: String) -> String? {
            let value = confirm[key]
            return value.isNullish ? nil : value.javaScriptString
        }
        title = text("title") ?? ""
        message = text("message") ?? ""
        confirmLabel = text("confirmLabel") ?? "Confirm"
        cancelLabel = text("cancelLabel") ?? "Cancel"
        isDestructive = confirm["variant"] == "danger"
    }
}

/// Presents the runtime's pending confirmation as an alert, like upstream
/// `ConfirmationDialogManager`.
struct ConfirmationPresenter: ViewModifier {
    let runtime: Runtime
    let isEnabled: Bool

    func body(content: Content) -> some View {
        let confirm = runtime.pendingConfirmation?.action.confirm ?? .undefined
        let dialog = ConfirmDialogContent(confirm)
        content.alert(
            dialog.title,
            // The buttons settle the confirmation. Dismissing the alert also
            // writes false here, so the setter must not cancel: it can run
            // before the confirm button's action.
            isPresented: Binding(get: { isEnabled && confirm.isTruthy }, set: { _ in })
        ) {
            Button(dialog.cancelLabel, role: .cancel) { runtime.cancel() }
            Button(dialog.confirmLabel, role: dialog.isDestructive ? .destructive : nil) { runtime.confirm() }
        } message: {
            Text(dialog.message)
        }
    }
}
