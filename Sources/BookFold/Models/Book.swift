//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// A scanned "virtual book" in the user's local library.
///
/// The skeleton model is deliberately plain; persistence (SwiftData) and
/// page storage land with the capture engine.
struct Book: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var createdAt: Date
    var pageCount: Int

    init(id: UUID = UUID(), title: String, createdAt: Date = Date(), pageCount: Int = 0) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.pageCount = pageCount
    }
}
