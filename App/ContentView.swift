import SwiftUI

struct ContentView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @EnvironmentObject var engine: LyricsEngine
    @AppStorage("keep_alive") private var keepAlive = true

    var body: some View {
        Group {
            if !auth.isLoggedIn {
                SetupView()
            } else {
                TabView {
                    LyricsView()
                        .tabItem { Label("Testi", systemImage: "music.note.list") }
                    SettingsView()
                        .tabItem { Label("Impostazioni", systemImage: "gearshape") }
                }
                .onAppear {
                    engine.start()
                    if keepAlive { KeepAlive.shared.start() }
                }
            }
        }
    }
}

private struct SetupView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @AppStorage("spotify_client_id") private var clientId = ""
    @AppStorage("spotify_redirect_uri") private var redirectUri = ""

    var body: some View {
        Form {
            Section("Spotify Developer App") {
                TextField("Client ID", text: $clientId)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                TextField("Redirect URI (https://...)", text: $redirectUri)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
            }
            Section {
                Button("Accedi con Spotify") { auth.login() }
                    .disabled(clientId.isEmpty || redirectUri.isEmpty)
            } footer: {
                Text("Crea un'app su developer.spotify.com, incolla qui il Client ID e il Redirect URI registrato (la pagina GitHub Pages del repo).")
            }
        }
    }
}

private struct LyricsView: View {
    @EnvironmentObject var engine: LyricsEngine

    var body: some View {
        VStack(spacing: 0) {
            if let t = engine.track {
                VStack(spacing: 2) {
                    Text(t.name).font(.headline).lineLimit(1)
                    Text(t.artist).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.top)
            } else {
                Text("Niente in riproduzione su Spotify")
                    .foregroundStyle(.secondary)
                    .padding(.top)
            }

            if let err = engine.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.top, 4)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    if engine.lines.isEmpty {
                        Text(engine.track == nil ? "" : "♪ Nessun testo sincronizzato per questo brano")
                            .foregroundStyle(.secondary)
                            .padding(.top, 60)
                    }
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(engine.lines.enumerated()), id: \.element.id) { i, line in
                            Text(line.text.isEmpty ? "♪" : line.text)
                                .font(.title2.weight(i == engine.currentIndex ? .bold : .regular))
                                .foregroundStyle(i == engine.currentIndex ? .primary : .secondary)
                                .id(i)
                        }
                    }
                    .padding()
                }
                .onChange(of: engine.currentIndex) { _, idx in
                    guard idx >= 0 else { return }
                    withAnimation { proxy.scrollTo(idx, anchor: .center) }
                }
            }
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var auth: SpotifyAuth
    @EnvironmentObject var engine: LyricsEngine
    @AppStorage("keep_alive") private var keepAlive = true

    var body: some View {
        Form {
            Section("Riproduzione") {
                Toggle("Resta attiva in background", isOn: $keepAlive)
                    .onChange(of: keepAlive) { _, on in
                        on ? KeepAlive.shared.start() : KeepAlive.shared.stop()
                    }
            } footer: {
                Text("Tiene viva l'app in auto con un audio silenzioso che non disturba Spotify.")
            }

            Section("Stato") {
                HStack {
                    Text("Brano")
                    Spacer()
                    Text(engine.track?.name ?? "—").foregroundStyle(.secondary)
                }
                HStack {
                    Text("Righe testo")
                    Spacer()
                    Text("\(engine.lines.count)").foregroundStyle(.secondary)
                }
                if let err = engine.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.orange)
                }
            }

            Section {
                Button("Logout", role: .destructive) {
                    engine.stop()
                    auth.logout()
                }
            }
        }
        .onAppear {
            if keepAlive { KeepAlive.shared.start() }
        }
    }
}
