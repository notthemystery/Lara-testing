//
//
// BundleResolver.swift
//
// lara
//

import Foundation
import UIKit

// MARK: - Final Model (KEYED BY DATA UUID)

struct ResolvedApp {
    let dataUUID: String
    let bundleID: String
    let bundlePath: String
    let name: String
    let icon: UIImage?
}

// MARK: - Resolver

final class BundleResolver {

    private let fm = FileManager.default

    private let bundleRoot = "/var/containers/Bundle/Application"
    private let dataRoot = "/var/mobile/Containers/Data/Application"

    // MARK: Public

    func resolveAll() -> [ResolvedApp] {

        let bundleMap = buildBundleMap()   // identifier → bundlePath
        var results: [ResolvedApp] = []

        guard let dataContainers = try? fm.contentsOfDirectory(atPath: dataRoot) else {
            return []
        }

        for dataUUID in dataContainers {

            let dataPath = dataRoot + "/" + dataUUID
            let metaPath = dataPath + "/.com.apple.mobile_container_manager.metadata.plist"

            guard
                let meta = NSDictionary(contentsOfFile: metaPath),
                let bundleID = meta["MCMMetadataIdentifier"] as? String
            else { continue }

            guard let bundlePath = bundleMap[bundleID] else {
                continue
            }

            let name = readName(bundlePath: bundlePath, fallback: bundleID)
            let icon = readIcon(bundlePath: bundlePath)

            results.append(
                ResolvedApp(
                    dataUUID: dataUUID,
                    bundleID: bundleID,
                    bundlePath: bundlePath,
                    name: name,
                    icon: icon
                )
            )
        }

        return results
    }

    // MARK: Bundle map (identifier → bundle path)

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
                else { continue }

                map[bundleID] = appPath
            }
        }

        return map
    }

    // MARK: Name

    private func readName(bundlePath: String, fallback: String) -> String {

        let infoPath = bundlePath + "/Info.plist"

        guard let info = NSDictionary(contentsOfFile: infoPath) else {
            return fallback
        }

        return info["CFBundleDisplayName"] as? String ??
               info["CFBundleName"] as? String ??
               fallback
    }

    // MARK: Icon

    private func readIcon(bundlePath: String) -> UIImage? {

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

        let path = bundlePath + "/" + iconName

        return UIImage(contentsOfFile: path)
            ?? UIImage(contentsOfFile: path + "@2x.png")
            ?? UIImage(contentsOfFile: path + ".png")
    }
}
