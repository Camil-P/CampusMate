import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                // .tabItem opisuje dugme u donjoj traci: tekst + SF Symbol ikona.
                .tabItem {
                    Label("Početna", systemImage: "house.fill")
                }

            CoursesView()
                .tabItem {
                    Label("Predmeti", systemImage: "books.vertical.fill")
                }

            TasksView()
                .tabItem {
                    Label("Zadaci", systemImage: "checklist")
                }

            DailyPlanView()
                .tabItem {
                    Label("Danas", systemImage: "calendar")
                }

            AIPlannerView()
                .tabItem {
                    Label("AI plan", systemImage: "sparkles")
                }
        }
    }
}

#Preview {
    RootTabView()
}
