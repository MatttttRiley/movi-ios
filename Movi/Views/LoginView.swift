import SwiftUI

/// Standard sign-in form (HIG: familiar words, system controls, autofill).
/// No jokes in the labels, no custom chrome: email + password, Sign In.
struct LoginView: View {
    @EnvironmentObject var app: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @FocusState private var focusedField: Field?

    enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)
                Text("Movi")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.moviAccent)
                    .accessibilityAddTraits(.isHeader)
                Text("Sign in to your account.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .password }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focusedField, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await submit() } }
                        .padding()
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                }
                if !app.error.isEmpty {
                    Text(app.error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await submit() }
                } label: {
                    if busy {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.moviAccent)
                .controlSize(.large)
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
