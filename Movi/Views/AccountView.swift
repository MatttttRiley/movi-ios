import SwiftUI

/// Account & Settings, opened from the person icon on Home.
///
/// The person icon used to log the user out the instant it was tapped.
/// It now opens this screen instead: profile info, settings, and Sign Out
/// as an explicit, confirmed button at the bottom — never an accidental
/// tap on the icon itself.
struct AccountView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject private var downloads = DownloadStore.shared
    @State private var confirmSignOut = false
    @State private var confirmClearDownloads = false

    var body: some View {
        List {
            Section("Profile") {
                if let name = app.profile?.name, !name.isEmpty {
                    LabeledContent("Profile", value: name)
                }
                if let username = app.user?.username, !username.isEmpty {
                    LabeledContent("Username", value: username)
                }
                if let email = app.user?.email, !email.isEmpty {
                    LabeledContent("Email", value: email)
                }
                if app.profiles.count > 1 {
                    ForEach(app.profiles) { p in
                        Button {
                            Task { await app.selectProfileFromPicker(p) }
                        } label: {
                            HStack {
                                Text(p.name)
                                Spacer()
                                if p.id == app.profile?.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Section("Settings") {
                NavigationLink("Downloads") {
                    DownloadsView()
                }
                Button("Clear All Downloads", role: .destructive) {
                    confirmClearDownloads = true
                }
                .disabled(downloads.items.isEmpty)
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    confirmSignOut = true
                }
            } footer: {
                Text("Movi \(appVersion)")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign Out", role: .destructive) {
                Task { await app.logout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to continue watching.")
        }
        .alert("Clear all downloads?", isPresented: $confirmClearDownloads) {
            Button("Clear All", role: .destructive) {
                for item in downloads.items {
                    downloads.delete(item)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Downloaded files will be deleted from this device. You can download them again anytime.")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }
}
