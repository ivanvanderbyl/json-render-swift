import JSONRender
import Testing
@testable import JSONRenderStandard
@testable import JSONRenderUI

// createStandardActionHandlers from packages/react-native/src/components/standard.tsx.
// System services stand in for React Native's Alert, Share and Linking.

@MainActor
@Suite("Standard actions")
struct StandardActionsTests {
    final class Recorder {
        var events: [String] = []
        var canOpen = true
    }

    func handlers(_ recorder: Recorder) -> [String: ActionHandler] {
        StandardActions.handlers(
            StandardActionOptions(
                navigate: { screen, params in recorder.events.append("navigate \(screen) \(params.map { "\(JSONValue.object($0))" } ?? "nil")") },
                goBack: { recorder.events.append("goBack") },
                onSetData: { path, value in recorder.events.append("setData \(path) \(value)") },
                onRefresh: { target in recorder.events.append("refresh \(target ?? "nil")") }
            ),
            services: SystemServices(
                alert: { alert in
                    let buttons = alert.buttons.map { $0.map { "\($0.text):\($0.style ?? "nil")" }.joined(separator: ",") } ?? "nil"
                    recorder.events.append("alert \(alert.title) \(alert.message ?? "nil") \(buttons)")
                },
                share: { share in recorder.events.append("share \(share.message) \(share.url ?? "nil") \(share.title ?? "nil")") },
                canOpenURL: { url in recorder.events.append("canOpen \(url)"); return recorder.canOpen },
                openURL: { url in recorder.events.append("open \(url)") }
            )
        )
    }

    @Test("has upstream's handlers, including setData and not the built-in state actions")
    func names() {
        #expect(Set(StandardActions.handlers().keys) == ["navigate", "goBack", "showAlert", "share", "openURL", "setData", "refresh"])
    }

    @Test("navigate passes the screen and params")
    func navigate() async throws {
        let recorder = Recorder()
        let handlers = handlers(recorder)
        _ = try await handlers["navigate"]?(["screen": "details", "params": ["id": 3]])
        _ = try await handlers["navigate"]?(["screen": "home", "params": nil])
        _ = try await handlers["goBack"]?([:])
        #expect(recorder.events == ["navigate details {\"id\":3}", "navigate home nil", "goBack"])
    }

    @Test("showAlert passes the title, message and button text and style")
    func showAlert() async throws {
        let recorder = Recorder()
        _ = try await handlers(recorder)["showAlert"]?([
            "title": "Saved", "message": nil,
            "buttons": [["text": "OK", "style": "cancel", "action": "ignored"], ["text": "More"]],
        ])
        _ = try await handlers(recorder)["showAlert"]?(["title": "Hi", "message": "There"])
        #expect(recorder.events == ["alert Saved nil OK:cancel,More:nil", "alert Hi There nil"])
    }

    @Test("share passes the message, url and title")
    func share() async throws {
        let recorder = Recorder()
        _ = try await handlers(recorder)["share"]?(["message": "Look", "url": "https://example.com", "title": nil])
        #expect(recorder.events == ["share Look https://example.com nil"])
    }

    @Test("openURL opens only what can be opened")
    func openURL() async throws {
        let recorder = Recorder()
        _ = try await handlers(recorder)["openURL"]?(["url": "https://example.com"])
        recorder.canOpen = false
        _ = try await handlers(recorder)["openURL"]?(["url": "nope://x"])
        #expect(recorder.events == ["canOpen https://example.com", "open https://example.com", "canOpen nope://x"])
    }

    @Test("setData and refresh call the host")
    func setDataAndRefresh() async throws {
        let recorder = Recorder()
        let handlers = handlers(recorder)
        _ = try await handlers["setData"]?(["statePath": "/a", "value": 1])
        _ = try await handlers["refresh"]?(["target": "feed"])
        _ = try await handlers["refresh"]?([:])
        #expect(recorder.events == ["setData /a 1", "refresh feed", "refresh nil"])
    }

    @Test("handlers without host callbacks do nothing")
    func withoutCallbacks() async throws {
        let handlers = StandardActions.handlers(services: SystemServices(alert: { _ in }, share: { _ in }, canOpenURL: { _ in false }, openURL: { _ in }))
        for name in ["navigate", "goBack", "setData", "refresh"] {
            _ = try await handlers[name]?(["screen": "x"])
        }
    }
}
