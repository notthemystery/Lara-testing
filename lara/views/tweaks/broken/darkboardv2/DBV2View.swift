import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Combine

final class SBLLogger: ObservableObject {
    static let shared = SBLLogger()

    @Published var text: String = ""

    func log(_ msg: String) {
        DispatchQueue.main.async {
            let line = "[\(Self.time())] \(msg)\n"
            self.text.append(line)
        }
    }

    static func time() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

struct SBLTheme: Identifiable {
    let id = UUID()
    let name: String
    let path: String
}

final class SBLThemeStore: ObservableObject {
    @Published var themes: [SBLTheme] = []
    @Published var selected: SBLTheme?

    let logger = SBLLogger.shared

    func addTheme(name: String, path: String) {
        let t = SBLTheme(name: name, path: path)
        themes.append(t)
        selected = t
        logger.log("Added theme: \(name)")
    }

    func select(_ theme: SBLTheme) {
        selected = theme
        logger.log("Selected theme: \(theme.name)")
    }
}

@_silgen_name("themer_apply_in_session")
func themer_apply_in_session(_ themePath: UnsafePointer<CChar>) -> Bool

@_silgen_name("themer_stop_in_session")
func themer_stop_in_session() -> Bool

struct DocumentPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder, .data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onPick(url)
        }
    }
}

struct DBV2View: View {
    @StateObject var store = SBLThemeStore()
    @StateObject var logger = SBLLogger.shared

    @State private var showImporter = false

    var body: some View {
        NavigationView {
            VStack(spacing: 12) {

                // Theme List
                List {
                    ForEach(store.themes) { theme in
                        HStack {
                            Text(theme.name)
                            Spacer()
                            if store.selected?.id == theme.id {
                                Text("Selected")
                                    .foregroundColor(.green)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.select(theme)
                        }
                    }
                }

                // Buttons
                HStack {
                    Button("Import Theme") {
                        showImporter = true
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Apply") {
                        applyTheme()
                    }
                    .buttonStyle(.bordered)

                    Button("Stop") {
                        _ = themer_stop_in_session()
                        logger.log("Stopped theming session")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                // Log view (replaces LogTextView)
                ScrollView {
                    Text(logger.text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .frame(height: 220)
                .background(Color.black.opacity(0.05))
            }
            .navigationTitle("DarkBoard V2")
        }
        .sheet(isPresented: $showImporter) {
            DocumentPicker { url in
                importTheme(from: url)
            }
        }
    }


    func importTheme(from url: URL) {
        let fm = FileManager.default
        logger.log("Importing: \(url.lastPathComponent)")

        guard url.startAccessingSecurityScopedResource() else {
            logger.log("Failed security scope access")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

            let pngs = contents.filter { $0.pathExtension.lowercased() == "png" }
            if pngs.isEmpty {
                logger.log("No PNG icons found")
                return
            }

            // Create temp theme folder in Documents
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
            let themeDir = docs.appendingPathComponent("SnowBoardLite/\(UUID().uuidString)")
            let iconsDir = themeDir.appendingPathComponent("Icons")

            try fm.createDirectory(at: iconsDir, withIntermediateDirectories: true)

            // Copy files
            for file in pngs {
                let dest = iconsDir.appendingPathComponent(file.lastPathComponent)
                try? fm.copyItem(at: file, to: dest)
            }

            store.addTheme(name: url.lastPathComponent, path: iconsDir.path)

        } catch {
            logger.log("Import error: \(error.localizedDescription)")
        }
    }

    func applyTheme() {
        guard let theme = store.selected else {
            logger.log("No theme selected")
            return
        }

        logger.log("Applying theme: \(theme.name)")

        let result = theme.path.withCString { ptr in
            themer_apply_in_session(ptr)
        }

        logger.log(result ? "Apply success" : "Apply failed")
    }
}
