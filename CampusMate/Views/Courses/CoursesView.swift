import SwiftUI

struct CoursesView: View {
    var body: some View {
        NavigationStack {
            Text("Uskoro")
                .foregroundStyle(.secondary)
                .navigationTitle("Predmeti")
        }
    }
}

#Preview {
    CoursesView()
}
