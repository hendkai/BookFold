//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

@main
struct BookFoldApp: App {
    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
    }
}
