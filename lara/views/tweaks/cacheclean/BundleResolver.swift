//
//
// BundleResolver.swift
//
// lara
//

import Foundation
import UIKit

// MARK: - Final Model (DATABASE ENTRY)

struct ResolvedApp {
    let dataUUID: String
    let bundleID: String
    let bundlePath: String
    let name: String
    let icon: UIImage?
}

// MARK: - Resolver (BUILDS DATA UUID DATABASE)

final class BundleResolver {

    private let fm = FileManager.default

    private let bundleRoot = "/var/containers/Bundle/Application"
    private let dataRoot = "/var/mobile/Containers/Data/Application"

    // MARK: Public API

    func resolveAll() -> [ResolvedApp] {

        // 🔥 STEP 1: Build bundleID → bundlePath map
        let bundleMap = buildBundleMap()

        // 🔥 STEP 2: Read data containers
        guard let dataContainers = try? fm.contentsOfDirectory(atPath: dataRoot) else {
            return []
        }

        var results: [ResolvedApp] = []

        // 🔥 STEP 3: Match DATA UUID → bundleID → bundle
        for dataUUID in dataContainers {

            let dataPath = dataRoot + "/" + dataUUID
            let metaPath = dataPath + "/.com.apple.mobile_container_manager.metadata.plist"

            guard
                let meta = NSDictionary(contentsOfFile: metaPath),
                let bundleID = meta["MCMMetadataIdentifier"] as? String,
                let bundlePath = bundleMap[bundleID]
            else {
                continue
            }

            results.append(
                ResolvedApp(
                    dataUUID: dataUUID,
                    bundleID: bundleID,
                    bundlePath: bundlePath,
                    name: readName(bundlePath),
                    icon: readIcon(bundlePath)
                )
            )
        }

        return results
    }

    // MARK: Build DB (bundleID → bundlePath)

    private func buildBundleMap() -> [String: String] {

        var map: [String: String] = [:]

        guard let roots = try? fm.contentsOfDirectory(atPath: bundleRoot) else {
            return map
        }

        for root in roots {

            let rootPath = bundleRoot + "/" + root

            guard let items = try? fm.contentsOfDirectory(atPath: rootPath) else {
                continue
            }

            for item in items where item.hasSuffix(".app") {

                let appPath = rootPath + "/" + item
                let metaPath = appPath + "/.com.apple.mobile_container_manager.metadata.plist"

                guard
                    let meta = NSDictionary(contentsOfFile: metaPath),
                    let bundleID = meta["MCMMetadataIdentifier"] as? String
                else {
                    continue
                }

                map[bundleID] = appPath
            }
        }

        return map
    }

    // MARK: Name

    private func readName(_ bundlePath: String) -> String {

        let infoPath = bundlePath + "/Info.plist"

        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return (bundlePath as NSString).lastPathComponent
        }

        return info["CFBundleDisplayName"] as? String ??
               info["CFBundleName"] as? String ??
               (bundlePath as NSString).lastPathComponent
    }

    // MARK: Icon

    private func readIcon(_ bundlePath: String) -> UIImage? {

        let infoPath = bundlePath + "/Info.plist"

        guard
            let info = NSDictionary(contentsOfFile: infoPath),
            let icons = info["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let iconName = files.last
        else {
            return UIImage(systemName: "app")
        }

        let basePath = bundlePath + "/" + iconName

        return UIImage(contentsOfFile: basePath)
            ?? UIImage(contentsOfFile: basePath + "@2x.png")
            ?? UIImage(contentsOfFile: basePath + ".png")
    }
}
