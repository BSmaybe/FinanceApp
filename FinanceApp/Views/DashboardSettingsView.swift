import SwiftUI

struct DashboardSettingsView: View {
    var showsDoneButton: Bool = false

    @AppStorage("dash.showQuickActions") private var showQuickActions = true
    @AppStorage("dash.showThisMonth") private var showThisMonth = true
    @AppStorage("dash.showCommitments") private var showCommitments = true
    @AppStorage("dash.showRecentActivity") private var showRecentActivity = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section(String(localized: "Dashboard Sections")) {
                Toggle(String(localized: "Quick Actions"), isOn: $showQuickActions)
                Toggle(String(localized: "This Month"), isOn: $showThisMonth)
                Toggle(String(localized: "Commitments"), isOn: $showCommitments)
                Toggle(String(localized: "Recent Activity"), isOn: $showRecentActivity)
            }
        }
        .navigationTitle(String(localized: "Dashboard Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsDoneButton {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done")) { dismiss() }
                }
            }
        }
    }
}
