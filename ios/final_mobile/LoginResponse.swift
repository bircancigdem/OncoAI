// LoginResponse.swift
import Foundation

struct LoginResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_at: String
}
