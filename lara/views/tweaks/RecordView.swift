import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RecordView: View {
    @ObservedObject var mgr: laramgr

    @State private var disabled = false
    @State private var isOverwriting = false

    private let target1 = "/var/mobile/Library/CallServices/Greetings/default/StartDisclosurewithTone.m4a"
    private let target2 = "/var/mobile/Library/CallServices/Greetings/default/StopDisclosure.caf"

    var body: some View {
        List {
            Section(header: HeaderLabel(text: "Status", icon: "info.circle")) {
                HStack {
                    Text("Status")
                    Spacer()

                    Text(disabled ? "Disabled" : "Enabled")
                        .foregroundColor(disabled ? .red : .green)
                        .monospaced()
                }
            }

            Section(header: HeaderLabel(text: "Actions", icon: "hammer")) {
                HStack {
                    Button("Disable") {
                        disableRecordNotify()
                    }
                    .disabled(disabled || isOverwriting)

                    Button("Enable") {
                        enableRecordNotify()
                    }
                    .disabled(!disabled || isOverwriting)
                }
            }
        }
        .navigationTitle("Call Record Notification")
        .onAppear {
            check()
        }
    }

    // MARK: - Backup Paths

    private var documents: URL {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]
    }

    private var backupFolder: URL {
        documents.appendingPathComponent("Backup")
    }

    private var backup1: URL {
        backupFolder.appendingPathComponent(
            "StartDisclosurewithTone.m4a"
        )
    }

    private var backup2: URL {
        backupFolder.appendingPathComponent(
            "StopDisclosure.caf"
        )
    }

    // MARK: - Bundled Sounds

    private var source1: String? {
        Bundle.main.path(
            forResource: "StartDisclosurewithTone",
            ofType: "m4a",
            inDirectory: "Sounds"
        )
    }

    private var source2: String? {
        Bundle.main.path(
            forResource: "StopDisclosure",
            ofType: "caf",
            inDirectory: "Sounds"
        )
    }

    // MARK: - Status Check

    private func check() {
        guard
            let attrs1 = try? FileManager.default.attributesOfItem(atPath: target1),
            let attrs2 = try? FileManager.default.attributesOfItem(atPath: target2),
            let size1 = attrs1[.size] as? NSNumber,
            let size2 = attrs2[.size] as? NSNumber
        else {
            disabled = false
            return
        }

        disabled = size1.intValue < 2048 ||
                   size2.intValue < 2048
    }

    // MARK: - Backup Creation

    private func createBackupsIfNeeded() {
        let fm = FileManager.default

        if !fm.fileExists(atPath: backupFolder.path) {
            try? fm.createDirectory(
                at: backupFolder,
                withIntermediateDirectories: true
            )
        }

        if !fm.fileExists(atPath: backup1.path) {
            try? fm.copyItem(
                at: URL(fileURLWithPath: target1),
                to: backup1
            )
        }

        if !fm.fileExists(atPath: backup2.path) {
            try? fm.copyItem(
                at: URL(fileURLWithPath: target2),
                to: backup2
            )
        }
    }

    // MARK: - Overwrite Helper

    @discardableResult
    private func overwrite(
        target: String,
        source: String
    ) -> Bool {

        let ok = mgr.vfsoverwritefromlocalpath(
            target: target,
            source: source
        )

        if ok {
            mgr.logmsg("overwrite ok: \(target)")
        } else {
            mgr.logmsg("overwrite failed: \(target)")
        }

        return ok
    }

    // MARK: - Disable Notification

    private func disableRecordNotify() {
        guard
            let source1,
            let source2
        else {
            mgr.logmsg("Bundled sound files missing")
            return
        }

        isOverwriting = true

        DispatchQueue.global(
            qos: .userInitiated
        ).async {

            self.createBackupsIfNeeded()

            let ok1 = self.overwrite(
                target: self.target1,
                source: source1
            )

            let ok2 = self.overwrite(
                target: self.target2,
                source: source2
            )

            DispatchQueue.main.async {
                self.isOverwriting = false

                if !(ok1 && ok2) {
                    self.mgr.logmsg(
                        "Failed disabling notification"
                    )
                }

                self.check()
            }
        }
    }

    // MARK: - Restore Notification

    private func enableRecordNotify() {
        let fm = FileManager.default

        guard
            fm.fileExists(atPath: backup1.path),
            fm.fileExists(atPath: backup2.path)
        else {
            mgr.logmsg("Backups not found")
            return
        }

        isOverwriting = true

        DispatchQueue.global(
            qos: .userInitiated
        ).async {

            let ok1 = self.overwrite(
                target: self.target1,
                source: self.backup1.path
            )

            let ok2 = self.overwrite(
                target: self.target2,
                source: self.backup2.path
            )

            DispatchQueue.main.async {
                self.isOverwriting = false

                if !(ok1 && ok2) {
                    self.mgr.logmsg(
                        "Failed restoring notification"
                    )
                }

                self.check()
            }
        }
    }
}
