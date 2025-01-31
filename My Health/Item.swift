//
//  Item.swift
//  My Health
//
//  Created by Jonathan Milligan on 10/15/24.
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
