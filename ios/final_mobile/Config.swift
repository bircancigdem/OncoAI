import Foundation

class Config {
    static var apiBaseURL: String {
        // Config.plist'i bul
        if let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
           let data = try? Data(contentsOf: url),
           let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let apiURL = dict["API_BASE_URL"] as? String {
            return apiURL
        }
        return "http://localhost:8000" // fallback
    }
}
