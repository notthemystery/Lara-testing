import SwiftUI
import UIKit
import Combine
import WebKit

// MARK: - Model

struct CacheApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String
    let appPath: String

    let icon: UIImage?

    let cacheSize: Int64
    let tmpSize: Int64
    let documentsSize: Int64

    let cachePath: String
    let tmpPath: String
    let documentsPath: String
}

// MARK: - Snapshot

struct StorageSnapshot: Identifiable {
    let id = UUID()
    let date = Date()
    let totalBytes: Int64
}

// MARK: - Manager

final class CleanerManager: ObservableObject {

    @Published var apps: [CacheApp] = []
    @Published var snapshots: [StorageSnapshot] = []

    @Published var isScanning = false
    @Published var scanProgress: Double = 0
    @Published var statusText = ""

    @Published var totalCacheBytes: Int64 = 0

    private let fm = FileManager.default
    private let dataRoot = "/private/var/mobile/Containers/Data/Application"

    // MARK: Scan

    func startScan(minSizeMB: Int64 = 4) {
        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        totalCacheBytes = 0
        statusText = "Scanning apps..."

        DispatchQueue.global(qos: .userInitiated).async {

            var results: [CacheApp] = []

            guard let containers = try? self.fm.contentsOfDirectory(atPath: self.dataRoot) else {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.statusText = "No containers found"
                }
                return
            }

            let total = max(containers.count, 1)
            var processed = 0

            for uuid in containers {

                let container = self.dataRoot + "/" + uuid

                let cache = container + "/Library/Caches"
                let tmp = container + "/tmp"
                let docs = container + "/Documents"

                guard self.fm.fileExists(atPath: cache) else { continue }

                let cacheSize = self.folderSize(cache)
                let tmpSize = self.folderSize(tmp)
                let docsSize = self.folderSize(docs)

                let totalSize = cacheSize + tmpSize + docsSize

                if totalSize < minSizeMB * 1024 * 1024 {
                    processed += 1
                    continue
                }

                let infoPath = self.findAppInfoPlist(in: container)
                let info = NSDictionary(contentsOfFile: infoPath ?? "")

                let bundleID = info?["CFBundleIdentifier"] as? String ?? uuid

                let name =
                    info?["CFBundleDisplayName"] as? String ??
                    info?["CFBundleName"] as? String ??
                    self.resolveAppName(from: bundleID) ??
                    bundleID

                let appPath = self.findAppBundle(in: container) ?? container

                let icon = self.loadIcon(appPath: appPath, info: info)

                results.append(CacheApp(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,
                    appPath: appPath,
                    icon: icon,
                    cacheSize: cacheSize,
                    tmpSize: tmpSize,
                    documentsSize: docsSize,
                    cachePath: cache,
                    tmpPath: tmp,
                    documentsPath: docs
                ))

                processed += 1

                let progress = Double(processed) / Double(total)

                DispatchQueue.main.async {
                    self.scanProgress = min(progress, 1.0)
                    self.statusText = "Scanning... \(Int(progress * 100))%"
                }
            }

            let totalBytes = results.reduce(0) {
                $0 + $1.cacheSize + $1.tmpSize + $1.documentsSize
            }

            DispatchQueue.main.async {
                self.apps = results.sorted { $0.cacheSize > $1.cacheSize }
                self.totalCacheBytes = totalBytes

                self.snapshots.append(StorageSnapshot(totalBytes: totalBytes))

                self.isScanning = false
                self.scanProgress = 1.0
                self.statusText = "Completed (\(results.count) apps)"
            }
        }
    }

    // MARK: Cleaners

    func cleanCache(_ app: CacheApp) {
        try? fm.removeItem(atPath: app.cachePath)
        try? fm.removeItem(atPath: app.tmpPath)
        startScan()
    }

    func cleanAll() {
        for app in apps {
            cleanCache(app)
        }
    }

    // MARK: WKWebView Cleaner

    func cleanWKWebView() {

        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]

        WKWebsiteDataStore.default().removeData(
            ofTypes: types,
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) {
            DispatchQueue.main.async {
                self.statusText = "WKWebView cleared"
            }
        }
    }

    func cleanURLCache() {
        URLCache.shared.removeAllCachedResponses()
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

    private func findAppBundle(in container: String) -> String? {
        guard let items = try? fm.contentsOfDirectory(atPath: container) else { return nil }

        return items.first(where: { $0.hasSuffix(".app") })
            .map { container + "/" + $0 }
    }

    private func findAppInfoPlist(in container: String) -> String? {
        guard let app = findAppBundle(in: container) else { return nil }
        return app + "/Info.plist"
    }

    // MARK: FIXED ICON LOADER

    private func loadIcon(appPath: String, info: NSDictionary?) -> UIImage? {

        let bundle = Bundle(path: appPath)

        if let bundle = bundle,
           let icon = bundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String {
            return UIImage(named: icon)
        }

        if let icons = info?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let name = files.last {

            return UIImage(contentsOfFile: appPath + "/" + name)
        }

        return UIImage(systemName: "app")
    }

    // MARK: Name resolver (best-effort)

    private func resolveAppName(from bundleID: String) -> String? {
        return nil
    }
}

// MARK: - UI

struct CacheView: View {

    @StateObject var mgr = CleanerManager()

    var body: some View {
        NavigationStack {

            VStack {

                Text("Clean Cache")
                    .font(.title2).bold()

                Text("\(mgr.totalCacheBytes / 1024 / 1024) MB Total")
                    .font(.title)

                ProgressView(value: mgr.scanProgress)

                Text(mgr.statusText)
                    .font(.caption)

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
                                    Text(app.name).bold()

                                    Text("Cache \(app.cacheSize / 1024 / 1024) MB")
                                    Text("Tmp \(app.tmpSize / 1024 / 1024) MB")
                                    Text("Docs \(app.documentsSize / 1024 / 1024) MB")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Tools") {
                        Button("Clear WKWebView") {
                            mgr.cleanWKWebView()
                        }

                        Button("Clear URLCache") {
                            mgr.cleanURLCache()
                        }

                        Button("Rescan") {
                            mgr.startScan()
                        }
                    }

                    Section("History") {
                        ForEach(mgr.snapshots) { snap in
                            Text("\(snap.totalBytes / 1024 / 1024) MB")
                                .font(.caption)
                        }
                    }
                }
            }
            .onAppear {
                mgr.startScan()
            }
        }
    }
}
