//
//  Item.swift
//  cashleak
//
//  Created by Anar Nur on 2026-08-09.
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
