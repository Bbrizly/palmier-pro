import SwiftUI

@MainActor
struct FilmStudioButton: View {
    let title: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Text(verbatim: title)
        }
    }
}

@MainActor
struct FilmStudioLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

@MainActor
struct FilmStudioTextField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        TextField(text: $text, prompt: Text(verbatim: placeholder)) {
            EmptyView()
        }
        .labelsHidden()
    }
}

@MainActor
struct FilmStudioDisclosureGroup<Content: View>: View {
    let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup {
            content
        } label: {
            Text(verbatim: title)
        }
    }
}
