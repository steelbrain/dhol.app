import Foundation

enum AppDefaults {
    private static let hotKeyKey = "dictationHotKey"
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    static var hotKey: HotKey {
        get {
            guard let data = UserDefaults.standard.data(forKey: hotKeyKey),
                  let value = try? decoder.decode(HotKey.self, from: data)
            else { return .default }
            return value
        }
        set {
            guard let data = try? encoder.encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: hotKeyKey)
        }
    }
}
