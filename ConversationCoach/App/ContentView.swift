import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationSplitView {
            SessionListView()
                .navigationTitle("Sessions")
        } detail: {
            if let session = appModel.selectedSession {
                ConversationWorkspaceView(session: session)
                    .id(session.id)
            } else {
                ContentUnavailableView(
                    "No Session",
                    systemImage: "text.bubble",
                    description: Text("Create a session to begin.")
                )
            }
        }
    }
}
