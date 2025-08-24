// LoginView.swift
import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthVM
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @FocusState private var focused: Field?

    enum Field { case email, pass }

    var body: some View {
        VStack(spacing: 20) {
            Text("OncoAI Hekim Girişi").font(.largeTitle).bold()

            TextField("E‑posta", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .focused($focused, equals: .email)
                .submitLabel(.next)

            SecureField("Şifre", text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 420)
                .focused($focused, equals: .pass)
                .submitLabel(.go)
                .onSubmit { login() }

            Button(action: login) {
                isBusy ? AnyView(ProgressView()) : AnyView(Text("Giriş Yap"))
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || email.isEmpty || password.isEmpty)
            .opacity(isBusy ? 0.7 : 1)

            if let err = auth.error {
                Text(err).foregroundColor(.red)
            }
        }
        .padding()
        .onAppear { focused = .email }
    }

    private func login() {
        guard !isBusy else { return }
        Task {
            await MainActor.run { isBusy = true }          // ✅ main thread
            defer { Task { await MainActor.run { isBusy = false } } } // ✅ her durumda kapanır
            await auth.login(email: email, password: password)
        }
    }
}
