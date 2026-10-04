import SwiftUI

struct ProfilesView: View {
    @EnvironmentObject var app: AppState
    @State private var busyId: Int?

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            VStack(spacing: 28) {
                Spacer()
                Text("Who's watching?")
                    .font(.largeTitle.bold())
                    .foregroundColor(.white)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 20)], spacing: 24) {
                    ForEach(app.profiles) { p in
                        Button {
                            Task { await pick(p) }
                        } label: {
                            VStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .fill(Color(hex: p.color) ?? .gray)
                                        .frame(width: 88, height: 88)
                                    if busyId == p.id {
                                        ProgressView().tint(.white)
                                    } else {
                                        Text(String(p.name.prefix(1)).uppercased())
                                            .font(.system(size: 36, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                }
                                Text(p.name)
                                    .foregroundColor(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                        .disabled(busyId != nil)
                    }
                }
                .padding(.horizontal, 40)
                if !app.error.isEmpty {
                    Text(app.error)
                        .foregroundColor(.red)
                        .font(.callout)
                }
                Spacer()
                Button("Log out") {
                    Task { await app.logout() }
                }
                .foregroundColor(.white.opacity(0.5))
                .padding(.bottom, 24)
            }
        }
    }

    private func pick(_ p: Profile) async {
        busyId = p.id
        await app.selectProfile(p)
        busyId = nil
    }
}
