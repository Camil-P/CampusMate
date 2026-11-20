import SwiftUI

struct DashboardView: View {
    var body: some View {
        NavigationStack {
            Text("Uskoro")
                .foregroundStyle(.secondary)
                // Naslov se stavlja na sadržaj UNUTAR NavigationStack-a, ne na sam stack.
                .navigationTitle("Početna")
        }
    }
}

#Preview {
    DashboardView()
}
