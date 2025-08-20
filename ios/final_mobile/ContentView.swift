import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: AuthVM
    
    var body: some View {
        Group {
            if auth.isAuthenticated {
                DashboardView()
            } else {
                LoginView()
            }
        }
        .animation(.default, value: auth.isAuthenticated)
    }
}
