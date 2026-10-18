//  BookFold — scan books into a local, private virtual library.
//  Copyright (C) 2026 BookFold Project / Hendrik Kaiser
//  SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Placeholder for the capture engine (edge detection, perspective
/// correction, spread splitting). The pipeline lands with the first
/// capture-engine milestone; camera code stays fully offline.
struct ScanView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Capture engine in progress",
                systemImage: "camera.metering.unknown",
                description: Text("The scanning pipeline — edge detection, perspective correction and two-page spread splitting — is under development.")
            )
            .navigationTitle("Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    ScanView()
}
