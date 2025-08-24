// TokenStore.swift
import Foundation

final class TokenStore {
    static let shared = TokenStore(); private init() {}

    private let key = "oncoai.jwt"
    var token: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set {
            if let v = newValue { UserDefaults.standard.set(v, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    func clear() { token = nil }
}
