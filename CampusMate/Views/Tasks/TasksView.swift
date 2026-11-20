import SwiftUI

struct TasksView: View {
    var body: some View {
        NavigationStack {
            Text("Uskoro")
                .foregroundStyle(.secondary)
                .navigationTitle("Zadaci")
        }
    }
}

#Preview {
    TasksView()
}
