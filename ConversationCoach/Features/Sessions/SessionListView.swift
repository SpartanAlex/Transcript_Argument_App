import SwiftUI

struct SessionListView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        List(selection: $appModel.selectedSessionID) {
            ForEach(appModel.sessions) { session in
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.title)
                        .font(.headline)
                        .lineLimit(1)

                    Text(session.updatedAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(session.id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appModel.createSession()
                } label: {
                    Label("New Session", systemImage: "plus")
                }
            }
        }
    }
}
