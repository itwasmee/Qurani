import ServiceManagement

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws { on ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
}
