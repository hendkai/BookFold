//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftData

/// A scanned "virtual book" in the user's local library.
@Model
final class Book {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Page.book)
    var pages: [Page]

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        pages: [Page] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.pages = pages
    }

    var pageCount: Int { pages.count }

    /// Pages in reading order.
    var sortedPages: [Page] { pages.sorted { $0.index < $1.index } }
}

/// One corrected page image belonging to a book.
@Model
final class Page {
    @Attribute(.unique) var id: UUID
    /// Reading-order index within the book (0-based, gap-free).
    var index: Int
    /// File name inside `PageImageStore.directory(for: book.id)`.
    var fileName: String

    var book: Book?

    init(id: UUID = UUID(), index: Int, fileName: String, book: Book? = nil) {
        self.id = id
        self.index = index
        self.fileName = fileName
        self.book = book
    }
}
