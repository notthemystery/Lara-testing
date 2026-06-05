import SwiftUI
import UIKit
import Combine
import WebKit

// MARK: - Model

struct CacheApp: Identifiable {
    let id: String
    let name: String
    let bundleID: String

    let appBundlePath: String
    let dataContainerPath: String

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

    // MARK: Roots

    private let dataRoot = "/var/mobile/Containers/Data/Application"
    private let bundleRoot = "/var/containers/Bundle/Application"

    // MARK: Scan

    func startScan(minSizeMB: Int64 = 4) {

        guard !isScanning else { return }

        isScanning = true
        scanProgress = 0
        totalCacheBytes = 0
        statusText = "Scanning apps..."

        DispatchQueue.global(qos: .userInitiated).async {

            var results: [CacheApp] = []

            let dataContainers = (try? self.fm.contentsOfDirectory(atPath: self.dataRoot)) ?? []
            let bundleMap = self.buildBundleMap()

            let total = max(dataContainers.count, 1)
            var processed = 0

            for uuid in dataContainers {

                let dataPath = self.dataRoot + "/" + uuid

                let cachePath = dataPath + "/Library/Caches"
                let tmpPath = dataPath + "/tmp"
                let docsPath = dataPath + "/Documents"

                guard self.fm.fileExists(atPath: cachePath) else {
                    processed += 1
                    continue
                }

                let cacheSize = self.folderSize(cachePath)
                let tmpSize = self.folderSize(tmpPath)
                let docsSize = self.folderSize(docsPath)

                let totalSize = cacheSize + tmpSize + docsSize

                if totalSize < minSizeMB * 1024 * 1024 {
                    processed += 1
                    continue
                }

                // MARK: Bundle ID from data container
                let bundleID = self.extractBundleID(from: dataPath) ?? uuid

                let bundlePath = bundleMap[bundleID]

                // MARK: Name (bundle first, fallback safe)
                let name: String = {
                    guard let bundlePath,
                          let info = NSDictionary(contentsOfFile: bundlePath + "/Info.plist") else {
                        return bundleID
                    }

                    return info["CFBundleDisplayName"] as? String ??
                           info["CFBundleName"] as? String ??
                           bundleID
                }()

                // MARK: Icon
                let icon = self.loadIcon(from: bundlePath)

                results.append(CacheApp(
                    id: bundleID,
                    name: name,
                    bundleID: bundleID,

                    appBundlePath: bundlePath ?? "",
                    dataContainerPath: dataPath,

                    icon: icon,

                    cacheSize: cacheSize,
                    tmpSize: tmpSize,
                    documentsSize: docsSize,

                    cachePath: cachePath,
                    tmpPath: tmpPath,
                    documentsPath: docsPath
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

    // MARK: Bundle Map (FIXED)

    private func buildBundleMap() -> [String: String] {

        var map: [String: String] = [:]

        guard let roots = try? fm.contentsOfDirectory(atPath: bundleRoot) else {
            return map
        }

        for root in roots {

            let rootPath = bundleRoot + "/" + root

            guard let apps = try? fm.contentsOfDirectory(atPath: rootPath) else { continue }

            for app in apps where app.hasSuffix(".app") {

                let appPath = rootPath + "/" + app
                let infoPath = appPath + "/Info.plist"

                guard let info = NSDictionary(contentsOfFile: infoPath),
                      let bundleID = info["CFBundleIdentifier"] as? String else {
                    continue
                }

                map[bundleID] = appPath
            }
        }

        return map
    }

    // MARK: Extract bundle ID (DATA container)

    private func extractBundleID(from dataPath: String) -> String? {

        let app = (try? fm.contentsOfDirectory(atPath: dataPath))?
            .first(where: { $0.hasSuffix(".app") })

        guard let app else { return nil }

        let plist = dataPath + "/" + app + "/Info.plist"

        return NSDictionary(contentsOfFile: plist)?["CFBundleIdentifier"] as? String
    }

    // MARK: Delete

    func deleteCache(_ app: CacheApp) {
        try? fm.removeItem(atPath: app.cachePath)
        try? fm.removeItem(atPath: app.tmpPath)
        startScan()
    }

    func deleteAll() {
        for app in apps {
            deleteCache(app)
        }
    }

    // MARK: WKWebView

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

    // MARK: Icon loader (FIXED)

    private func loadIcon(from bundlePath: String?) -> UIImage? {

        guard let bundlePath else {
            return UIImage(systemName: "app")
        }

        let infoPath = bundlePath + "/Info.plist"

        guard let info = NSDictionary(contentsOfFile: infoPath),
              let icons = info["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let iconName = files.last else {
            return UIImage(systemName: "app")
        }

        let iconPath = bundlePath + "/" + iconName
        return UIImage(contentsOfFile: iconPath)
    }

    // MARK: Size

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
                            .swipeActions {
                                Button(role: .destructive) {
                                    mgr.deleteCache(app)
                                } label: {
                                    Text("Delete")
                                }
                            }
                        }
                    }

                    Section("Tools") {

                        Button("Delete ALL Cache") {
                            mgr.deleteAll()
                        }
                        .foregroundStyle(.red)

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
                }
            }
            .onAppear {
                mgr.startScan()
            }
        }
    }
}
