import SwiftUI

@main
struct final_mobileApp: App {
    @StateObject private var auth = AuthVM()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)   // ✅
        }
    }
}
