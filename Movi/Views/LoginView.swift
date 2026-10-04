import SwiftUI

struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        ZStack {
            Color.moviBackground.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Text("Movi")
                    .font(.system(size: 52, weight: .black))
                    .foregroundColor(.moviAccent)
                Text("Who goes there?")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.8))
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .padding()
                        .background(Color.moviCard)
                        .cornerRadius(10)
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .padding()
                        .background(Color.moviCard)
                        .cornerRadius(10)
                }
                .foregroundColor(.white)
                if !app.error.isEmpty {
                    Text(app.error)
                        .font(.callout)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await submit() }
                } label: {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Enter")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .moviPlayChrome()
                .disabled(busy || email.isEmpty || password.isEmpty)
                Spacer()
            }
            .padding(32)
        }
        .onAppear { focusedField = .email }
    }

    private func submit() async {
        guard !busy, !email.isEmpty, !password.isEmpty else { return }
        busy = true
        focusedField = nil
        await app.login(email: email, password: password)
        busy = false
    }
}
