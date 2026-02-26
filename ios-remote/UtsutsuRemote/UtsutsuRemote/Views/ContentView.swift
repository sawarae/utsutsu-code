import SwiftUI

struct ContentView: View {
    @StateObject private var connection = RelayConnection()
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            SessionView(connection: connection)
                .tabItem {
                    Label("セッション", systemImage: "terminal.fill")
                }
                .tag(0)

            TtsRequestView(connection: connection)
                .tabItem {
                    Label("お願い", systemImage: "speaker.wave.2.fill")
                }
                .tag(1)

            ConnectionView(connection: connection)
                .tabItem {
                    Label("接続", systemImage: "network")
                }
                .tag(2)
        }
        .tint(.purple)
    }
}

#Preview {
    ContentView()
}
