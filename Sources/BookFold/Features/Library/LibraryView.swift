//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftData
import SwiftUI

/// The user's local library of scanned virtual books.
struct LibraryView: View {
    @Query(sort: \Book.createdAt, order: .reverse)
    private var books: [Book]

    @Environment(\.modelContext) private var modelContext

    @State private var isScannerPresented = false
    @State private var bookToRename: Book?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            Group {
                if books.isEmpty {
                    ContentUnavailableView(
                        "No books yet",
                        systemImage: "books.vertical",
                        description: Text("Scan your first book to add it to your library. Everything stays on this device.")
                    )
                } else {
                    List {
                        ForEach(books) { book in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(book.title)
                                    .font(.headline)
                                Text("\(book.pageCount) pages")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    delete(book)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    newTitle = book.title
                                    bookToRename = book
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isScannerPresented = true
                    } label: {
                        Label("Scan", systemImage: "camera.viewfinder")
                    }
                }
            }
            .sheet(isPresented: $isScannerPresented) {
                ScanView()
            }
            .alert("Rename book", isPresented: Binding(
                get: { bookToRename != nil },
                set: { if !$0 { bookToRename = nil } }
            )) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    if let book = bookToRename {
                        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            book.title = trimmed
                            try? modelContext.save()
                        }
                    }
                    bookToRename = nil
                }
                Button("Cancel", role: .cancel) { bookToRename = nil }
            }
        }
    }

    private func delete(_ book: Book) {
        PageImageStore.standard.deleteBook(book.id)
        modelContext.delete(book)
        try? modelContext.save()
    }
}

#Preview {
    LibraryView()
        .modelContainer(for: [Book.self, Page.self], inMemory: true)
}
