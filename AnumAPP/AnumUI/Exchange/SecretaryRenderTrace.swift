import Foundation

#if DEBUG
@MainActor
enum SecretaryRenderTrace {
    private static var lastWorkspaceKey: String = ""
    private static var lastDashboardKey: String = ""

    static func workspaceBodyIfChanged(_ key: String) {
        guard key != lastWorkspaceKey else { return }
        lastWorkspaceKey = key
        Swift.print("[SecretaryRender] Workspace body render reason=\(key)")
    }

    static func dashboardBodyIfChanged(_ key: String) {
        guard key != lastDashboardKey else { return }
        lastDashboardKey = key
        Swift.print("[SecretaryRender] Dashboard body render reason=\(key)")
    }
}
#endif
