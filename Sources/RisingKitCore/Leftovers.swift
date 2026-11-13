import Foundation

/// 앱을 지운 뒤에도 남는 설정·캐시 파일을 찾기 위한 이름 맞춤.
/// 다른 앱의 파일을 잘못 고르지 않도록 일부러 보수적으로 맞춘다.
public enum Leftovers {
    /// ~/Library 아래에서 훑어볼 폴더들
    public static let libraryFolders = [
        "Application Support", "Caches", "Preferences", "Logs", "Containers", "Saved Application State",
        "HTTPStorages", "WebKit", "Cookies", "LaunchAgents", "Application Scripts",
    ]

    /// 앱 이름으로도 맞춰 보는 폴더 (여기서는 폴더 이름이 앱 이름인 경우가 흔하다)
    static let nameMatchFolders: Set<String> = ["Application Support", "Caches", "Logs"]

    /// `folder`(~/Library 아래 폴더 이름) 안의 `entry` 가 이 앱의 것인지.
    public static func matches(entry: String, in folder: String, bundleId: String, appName: String) -> Bool {
        let name = entry.lowercased()
        let id = bundleId.lowercased()

        // 번들 id: 점이 둘 이상 있는 제대로 된 id 일 때만, 정확히 같거나 "id." 으로 시작하는 것
        // (com.x.app.plist, com.x.app.savedState, com.x.app.helper). "com.x.app2" 는 다른 앱이다.
        if id.split(separator: ".").count >= 3, !id.hasPrefix("com.apple.") {
            if name == id || name.hasPrefix(id + ".") { return true }
        }

        // 앱 이름: 폴더 이름이 앱 이름과 정확히 같을 때만. 너무 짧거나 흔한 이름은 맞추지 않는다.
        let app = appName.lowercased()
        if nameMatchFolders.contains(folder), app.count >= 4, name == app { return true }
        return false
    }

    /// 사람이 읽기 좋은 크기
    public static func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        if mb >= 1 { return String(format: "%.0f MB", mb) }
        return String(format: "%.0f KB", max(Double(bytes) / 1024, bytes > 0 ? 1 : 0))
    }
}
