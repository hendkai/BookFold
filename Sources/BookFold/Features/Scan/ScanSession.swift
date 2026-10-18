//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import SwiftData

/// Accumulates the corrected pages of one scanning session and persists them
/// as a new `Book` (pages in reading order, images via `PageImageStore`).
@MainActor
final class ScanSession {
    struct CapturedPage: Identifiable, Sendable {
        let id = UUID()
        /// Reading-order index within the session.
        let index: Int
        let image: CGImage
    }

    private(set) var pages: [CapturedPage] = []
    let startedAt = Date()

    var isEmpty: Bool { pages.isEmpty }

    /// Appends newly captured pages (a spread contributes two, in reading
    /// order). Returns the indices the pages received.
    @discardableResult
    func add(_ images: [CGImage]) -> [Int] {
        var indices: [Int] = []
        for image in images {
            let index = pages.count
            pages.append(CapturedPage(index: index, image: image))
            indices.append(index)
        }
        return indices
    }

    /// Removes the most recently captured page (undo).
    @discardableResult
    func removeLast() -> CapturedPage? {
        pages.popLast()
    }

    /// Default title for a freshly scanned book ("Book — Oct 18, 2026");
    /// editable in the library afterwards.
    nonisolated static func defaultTitle(for date: Date, now: () -> Date = Date.init) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return "Book — \(formatter.string(from: date))"
    }

    /// Persists the session as a new book. The caller owns the `ModelContext`
    /// (SwiftData views pass `modelContext` from the environment).
    @discardableResult
    func save(
        modelContext: ModelContext,
        imageStore: PageImageStore = .standard
    ) throws -> Book {
        let book = Book(
            title: ScanSession.defaultTitle(for: startedAt),
            createdAt: startedAt
        )
        modelContext.insert(book)

        for page in pages {
            let fileName = try imageStore.write(page.image, bookID: book.id, index: page.index)
            let pageModel = Page(index: page.index, fileName: fileName, book: book)
            modelContext.insert(pageModel)
        }

        try modelContext.save()
        return book
    }
}
