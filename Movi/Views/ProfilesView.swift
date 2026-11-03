import SwiftUI

/// Profile picker, shown ONLY when an account has more than one profile.
/// Single-profile accounts never see this screen (AppState auto-selects).
/// Standard list rows, not a grid of colored circles.
struct ProfilesView: View {
    @EnvironmentObject var app: AppState
    @State private var busyId: Int?

    var body: some View {
        NavigationStack {
            List(app.profiles) { p in
                Button {
                    Task { await pick(p) }
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: p.color ?? "") ?? .gray)
                            .frame(width: 36, height: 36)
                            .overlay {
                                if busyId == p.id {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(String(p.name.prefix(1)).uppercased())
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(p.name)
                    }
                }
                .disabled(busyId != nil)
            }
            .navigationTitle("Who's Watching?")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Sign Out") { Task { await app.logout() } }
                }
            }
            if !app.error.isEmpty {
                Text(app.error).foregroundStyle(.red).font(.callout)
            }
        }
    }

    private func pick(_ p: Profile) async {
        busyId = p.id
        await app.selectProfileFromPicker(p)
        busyId = nil
    }
}
