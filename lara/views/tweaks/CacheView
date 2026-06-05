import SwiftUI
import UIKit

// MARK: - Model

struct CacheApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let appPath: String
    let icon: UIImage?
    let cacheSize: Int64
    let cachePath: String
}

// MARK: - Manager

final class CleanerManager: ObservableObject {

    @Published var apps: [CacheApp] = []

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var statusText = ""

    @Published var totalCacheBytes: Int64 = 0

    private let fm = FileManager.default

    // MARK: Auto Scan

    func startScan(minSizeMB: Int64 = 4) {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        totalCacheBytes = 0
        statusText = "Scanning apps..."

        DispatchQueue.global(qos: .userInitiated).async {

            let base = "/private/var/containers/Bundle/Application"

            var results: [CacheApp] = []

            guard let bundles = try? self.fm.contentsOfDirectory(atPath: base) else {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.statusText = "No apps found"
                }
                return
            }

            let total = max(bundles.count, 1)

            for (index, bundle) in bundles.enumerated() {

                let appContainer = base + "/" + bundle

                guard let items = try? self.fm.contentsOfDirectory(atPath: appContainer) else { continue }

                for item in items where item.hasSuffix(".app") {

                    let appPath = appContainer + "/" + item
                    let cachePath = appPath + "/Library/Caches"

                    guard self.fm.fileExists(atPath: cachePath) else { continue }

                    let size = self.folderSize(cachePath)
                    guard size > (minSizeMB * 1024 * 1024) else { continue }

                    let info = NSDictionary(contentsOfFile: appPath + "/Info.plist")
                    let bundleID = info?["CFBundleIdentifier"] as? String ?? UUID().uuidString

                    let name =
                        info?["CFBundleDisplayName"] as? String ??
                        info?["CFBundleName"] as? String ??
                        item

                    let icon = self.loadIcon(appPath: appPath, info: info)

                    results.append(CacheApp(
                        id: bundleID,
                        name: name,
                        bundleID: bundleID,
                        appPath: appPath,
                        icon: icon,
                        cacheSize: size,
                        cachePath: cachePath
                    ))

                    break
                }

                // update progress LIVE
                let progress = Double(index + 1) / Double(total)

                DispatchQueue.main.async {
                    self.scanProgress = progress
                    self.statusText = "Scanning... \(Int(progress * 100))%"
                }
            }

            let totalBytes = results.reduce(0) { $0 + $1.cacheSize }

            DispatchQueue.main.async {
                self.apps = results.sorted { $0.cacheSize > $1.cacheSize }
                self.totalCacheBytes = totalBytes
                self.isScanning = false
                self.statusText = "Found \(results.count) apps"
            }
        }
    }

    // MARK: TMP Cleaner

    func cleanTMP() {
        let tmp = "/var/mobile/tmp"
        guard let files = try? fm.contentsOfDirectory(atPath: tmp) else { return }

        for file in files {
            try? fm.removeItem(atPath: tmp + "/" + file)
        }
    }

    // MARK: Cache Delete

    func deleteCache(_ app: CacheApp) {
        try? fm.removeItem(atPath: app.cachePath)
        try? fm.createDirectory(atPath: app.cachePath, withIntermediateDirectories: true)
        startScan()
    }

    func deleteAll() {
        for app in apps {
            deleteCache(app)
        }
        startScan()
    }

    // MARK: Helpers

    private func folderSize(_ path: String) -> Int64 {
        guard let e = fm.enumerator(atPath: path) else { return 0 }

        var size: Int64 = 0

        for case let file as String in e {
            let full = (path as NSString).appendingPathComponent(file)

            if let attrs = try? fm.attributesOfItem(atPath: full),
               let fileSize = attrs[.size] as? NSNumber {
                size += fileSize.int64Value
            }
        }

        return size
    }

    private func loadIcon(appPath: String, info: NSDictionary?) -> UIImage? {
        guard let icons = info?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else {
            return UIImage(systemName: "app")
        }

        let path = appPath + "/" + name

        return UIImage(contentsOfFile: path)
            ?? UIImage(contentsOfFile: path + "@2x.png")
            ?? UIImage(contentsOfFile: path + ".png")
    }
}

// MARK: - UI

struct CleanerView: View {

    @StateObject var mgr = CleanerManager()

    var body: some View {
        NavigationStack {

            VStack(spacing: 0) {

                VStack(spacing: 10) {

                    Text("Cache Found")
                        .font(.headline)

                    Text("\(mgr.totalCacheBytes / 1024 / 1024) MB")
                        .font(.system(size: 34, weight: .bold))

                    ProgressView(value: Double(mgr.totalCacheBytes))
                        .padding(.horizontal)

                    ProgressView(value: mgr.scanProgress)
                        .padding(.horizontal)

                    Text(mgr.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()

                Divider()

                List {

                    Section("Apps") {

                        ForEach(mgr.apps) { app in

                            HStack {
                                if let icon = app.icon {
                                    Image(uiImage: icon)
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .cornerRadius(8)
                                } else {
                                    Image(systemName: "app")
                                }

                                VStack(alignment: .leading) {
                                    Text(app.name)
                                    Text("\(app.cacheSize / 1024 / 1024) MB cache")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    mgr.deleteCache(app)
                                } label: {
                                    Text("Delete")
                                }
                            }
                        }
                    }

                    Section {
                        Button("Delete All Cache") {
                            mgr.deleteAll()
                        }
                        .foregroundStyle(.red)

                        Button("Clean TMP") {
                            mgr.cleanTMP()
                        }
                    }
                }
            }
            .navigationTitle("Live Cleaner")

            .onAppear {
                mgr.startScan()
            }
        }
    }
}
