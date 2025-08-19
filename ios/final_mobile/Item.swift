//
//  Item.swift
//  final_mobile
//
//  Created by Çiğdem Bircan on 19.08.2025.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
