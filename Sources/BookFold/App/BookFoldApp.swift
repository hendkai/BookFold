//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftData
import SwiftUI

@main
struct BookFoldApp: App {
    /// Local SwiftData store in the app container — no CloudKit, no syncing.
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Book.self, Page.self)
        } catch {
            // A corrupt local store must never crash the app; fall back to
            // in-memory so scanning still works this session.
            assertionFailure("BookFold: falling back to in-memory store: \(error)")
            container = try! ModelContainer(
                for: Book.self, Page.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .modelContainer(container)
    }
}
