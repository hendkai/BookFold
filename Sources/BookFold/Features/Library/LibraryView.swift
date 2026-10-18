//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The user's local library of scanned virtual books.
struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var isScannerPresented = false

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
                    List(books) { book in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title)
                                .font(.headline)
                            Text("\(book.pageCount) pages")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
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
        }
    }
}

#Preview {
    LibraryView()
}
