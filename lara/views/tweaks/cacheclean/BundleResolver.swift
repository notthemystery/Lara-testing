//
//  BundleResolver.swift
//  lara
//

import UIKit

struct BundleInfo {
    let name: String
    let bundleID: String
    let bundlePath: String
    let icon: UIImage?
}

/// Same logic as DecryptView.loadApps() name/icon extraction
func resolveBundleInfo(bundleID: String) -> BundleInfo? {

    let bundleFolder = "/private/var/containers/Bundle/Application"
    let fm = FileManager.default

    guard let bundles = try? fm.contentsOfDirectory(atPath: bundleFolder) else {
        return nil
    }

    for bundle in bundles {

        let appPath = bundleFolder + "/" + bundle

        guard let contents = try? fm.contentsOfDirectory(atPath: appPath) else {
            continue
        }

        for item in contents where item.hasSuffix(".app") {

            let fullAppPath = appPath + "/" + item
            let infoPath = fullAppPath + "/Info.plist"

            guard let info = NSDictionary(contentsOfFile: infoPath),
                  let currentBundleID = info["CFBundleIdentifier"] as? String,
                  currentBundleID == bundleID else {
                continue
            }

            // MARK: Name (EXACT same logic as your working code)
            let name =
                (info["CFBundleDisplayName"] as? String) ??
                (info["CFBundleName"] as? String) ??
                (item as NSString).deletingPathExtension

            // MARK: Icon (EXACT same fallback chain)
            var icon: UIImage? = nil

            if let icons = info["CFBundleIcons"] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let iconfiles = primary["CFBundleIconFiles"] as? [String],
               let iconname = iconfiles.last {

                let iconpath = fullAppPath + "/" + iconname

                if let img = UIImage(contentsOfFile: iconpath) {
                    icon = img
                } else if let img = UIImage(contentsOfFile: iconpath + "@2x.png") {
                    icon = img
                } else if let img = UIImage(contentsOfFile: iconpath + ".png") {
                    icon = img
                }
            }

            return BundleInfo(
                name: name,
                bundleID: currentBundleID,
                bundlePath: fullAppPath,
                icon: icon
            )
        }
    }

    return nil
}
