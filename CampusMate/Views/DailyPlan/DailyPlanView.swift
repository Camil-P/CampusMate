import SwiftUI

struct DailyPlanView: View {
    var body: some View {
        NavigationStack {
            Text("Uskoro")
                .foregroundStyle(.secondary)
                .navigationTitle("Danas")
        }
    }
}

#Preview {
    DailyPlanView()
}
