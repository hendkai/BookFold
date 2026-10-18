//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import SwiftData
import XCTest

@testable import BookFold

@MainActor
final class ScanSessionTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var store: PageImageStore!
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookfold-tests-\(UUID().uuidString)", isDirectory: true)
        store = PageImageStore(root: tempRoot)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Book.self, Page.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() async throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func page(_ value: UInt8) -> CGImage {
        TestImageFactory.solid(width: 60, height: 80, r: CGFloat(value) / 255, g: 0.9, b: 0.85)
    }

    func testSessionPersistsBookWithOrderedPages() throws {
        let session = ScanSession()

        // Simulated scanning: spread (2 pages), single (1), spread (2).
        session.add([page(60), page(70)]) // spread 1 → left, right
        session.add([page(80)]) // single page
        session.add([page(90), page(100)]) // spread 2

        XCTAssertEqual(session.pages.count, 5)
        XCTAssertEqual(session.pages.map(\.index), [0, 1, 2, 3, 4])

        let book = try session.save(modelContext: context, imageStore: store)

        XCTAssertEqual(book.pageCount, 5)
        XCTAssertFalse(book.title.isEmpty)
        XCTAssertEqual(book.sortedPages.map(\.index), Array(0..<5), "indices must be gap-free and ordered")

        // Every page image exists on disk and decodes.
        for pageModel in book.sortedPages {
            let url = store.url(bookID: book.id, fileName: pageModel.fileName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(url.path)")
            XCTAssertNotNil(store.image(bookID: book.id, fileName: pageModel.fileName))
        }

        // Persisted store round-trip.
        let fetched = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.pageCount, 5)
    }

    func testUndoRemovesLastPage() {
        let session = ScanSession()
        session.add([page(50), page(60)])
        session.add([page(70)])

        let removed = session.removeLast()
        XCTAssertEqual(removed?.index, 2)
        XCTAssertEqual(session.pages.count, 2)
        XCTAssertEqual(session.pages.last?.index, 1)

        // The next capture continues at index 2.
        session.add([page(80)])
        XCTAssertEqual(session.pages.map(\.index), [0, 1, 2])
    }

    func testTitleIsEditableAfterSave() throws {
        let session = ScanSession()
        session.add([page(50)])
        let book = try session.save(modelContext: context, imageStore: store)

        XCTAssertEqual(book.title, ScanSession.defaultTitle(for: session.startedAt))
        book.title = "My Custom Title"
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Book>()).first
        XCTAssertEqual(fetched?.title, "My Custom Title")
    }

    func testDefaultTitleContainsFormattedDate() {
        let date = Date(timeIntervalSince1970: 1_761_580_000) // fixed instant
        let title = ScanSession.defaultTitle(for: date)
        XCTAssertTrue(title.hasPrefix("Book — "), "got: \(title)")
        XCTAssertGreaterThan(title.count, 8)
    }

    func testDeleteBookRemovesFiles() throws {
        let session = ScanSession()
        session.add([page(40), page(50)])
        let book = try session.save(modelContext: context, imageStore: store)

        let dir = store.directory(for: book.id)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))

        store.deleteBook(book.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
    }
}
