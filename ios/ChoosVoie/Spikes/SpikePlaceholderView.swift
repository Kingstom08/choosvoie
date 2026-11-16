import SwiftUI

struct SpikePlaceholderView: View {
    let title: String

    var body: some View {
        ContentUnavailableView("Henüz uygulanmadı", systemImage: "hammer",
                               description: Text(title))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
