//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Stores page images as JPEG files inside the app container
/// (`Application Support/BookFoldPages/<book id>/page-0001.jpg`).
///
/// Deliberately plain file storage: no iCloud documents, no CloudKit, no
/// background syncing — scans never leave the device.
struct PageImageStore: Sendable {
    /// Default store inside the local app container.
    static let standard = PageImageStore()

    let root: URL

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            self.root = (support ?? FileManager.default.temporaryDirectory)
                .appendingPathComponent("BookFoldPages", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }

    func directory(for bookID: UUID) -> URL {
        root.appendingPathComponent(bookID.uuidString, isDirectory: true)
    }

    func url(bookID: UUID, fileName: String) -> URL {
        directory(for: bookID).appendingPathComponent(fileName)
    }

    /// Writes one page; returns the stored file name.
    @discardableResult
    func write(_ image: CGImage, bookID: UUID, index: Int) throws -> String {
        let dir = directory(for: bookID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fileName = String(format: "page-%04d.jpg", index)
        let fileURL = dir.appendingPathComponent(fileName)

        guard let destination = CGImageDestinationCreateWithURL(
            fileURL as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: fileURL.path,
            ])
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.85]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [
                NSFilePathErrorKey: fileURL.path,
            ])
        }
        return fileName
    }

    func image(bookID: UUID, fileName: String) -> CGImage? {
        let fileURL = url(bookID: bookID, fileName: fileName)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Removes all files of a book (cascade to pages is handled by SwiftData).
    func deleteBook(_ bookID: UUID) {
        try? FileManager.default.removeItem(at: directory(for: bookID))
    }
}
