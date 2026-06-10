import AuthenticationServices
import CryptoKit
import Foundation

// OAuth 2.0 Authorization Code + PKCE. No client secret needed.
// Redirect: HTTPS page (GitHub Pages) that bounces to dynamiclyrics://callback
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    @Published var isLoggedIn: Bool = Keychain.get("spotify_refresh_token") != nil

    // Set once in the app's setup screen, stored in UserDefaults.
    var clientId: String { UserDefaults.standard.string(forKey: "spotify_client_id") ?? "" }
    var redirectUri: String { UserDefaults.standard.string(forKey: "spotify_redirect_uri") ?? "" }

    private var codeVerifier = ""
    private var accessToken: String?
    private var tokenExpiry = Date.distantPast
    private var session: ASWebAuthenticationSession?

    func login() {
        codeVerifier = Self.randomVerifier()
        let challenge = Self.codeChallenge(for: codeVerifier)
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirectUri),
            .init(name: "scope", value: "user-read-playback-state user-read-currently-playing"),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "code_challenge", value: challenge),
        ]
        let s = ASWebAuthenticationSession(url: comps.url!, callbackURLScheme: "dynamiclyrics") { [weak self] url, _ in
            guard let url,
                  let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else { return }
            Task { await self?.exchange(code: code) }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    func logout() {
        Keychain.delete("spotify_refresh_token")
        accessToken = nil
        isLoggedIn = false
    }

    func validAccessToken() async throws -> String {
        if let t = accessToken, tokenExpiry > Date().addingTimeInterval(60) { return t }
        guard let refresh = Keychain.get("spotify_refresh_token") else {
            throw URLError(.userAuthenticationRequired)
        }
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": clientId,
        ]
        let resp = try await tokenRequest(body: body)
        store(resp)
        return resp.accessToken
    }

    private func exchange(code: String) async {
        let body = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectUri,
            "client_id": clientId,
            "code_verifier": codeVerifier,
        ]
        if let resp = try? await tokenRequest(body: body) {
            store(resp)
            isLoggedIn = true
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Int
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    private func tokenRequest(body: [String: String]) async throws -> TokenResponse {
        var req = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // invalid_grant etc: refresh token dead, force re-login
            if status == 400, body["grant_type"] == "refresh_token" {
                Keychain.delete("spotify_refresh_token")
                isLoggedIn = false
            }
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "SpotifyAuth", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "token HTTP \(status) \(detail.prefix(120))"])
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    private func store(_ resp: TokenResponse) {
        accessToken = resp.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(resp.expiresIn))
        if let r = resp.refreshToken { Keychain.set(r, key: "spotify_refresh_token") }
    }

    private static func randomVerifier() -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<64).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

extension SpotifyAuth: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
