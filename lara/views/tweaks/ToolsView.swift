import SwiftUI

struct procentry: Identifiable, Hashable {
    let id = UUID()
    let pid: Int32
    let name: String
}

struct ToolsView: View {
    @ObservedObject private var mgr = laramgr.shared
    @State private var isaslr: Bool = aslrstate
    @State var showtoken: Bool = false
    @AppStorage("lara.sbx.issuedToken")
    private var token: String = ""
    @State private var issueclass: tokenclass = .rw
    @State private var issuepath: String = "/"
    @State private var uid: uid_t = getuid()
    @State private var pid: pid_t = getpid()
    @State private var status: String?
    @State private var crashname: String = "SpringBoard"
    @State private var pausedProcesses: Set<String> = []
    @State private var proc_sbx: UInt64 = 0

    private enum tokenclass: String, CaseIterable, Identifiable {
        case read = "com.apple.app-sandbox.read"
        case write = "com.apple.app-sandbox.write"
        case rw = "com.apple.app-sandbox.read-write"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .read: return "read"
            case .write: return "write"
            case .rw: return "read-write"
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {

                if !mgr.dsready {
                    Section {
                        Text("Kernel R/W is not ready. Run the exploit first.")
                            .foregroundColor(.secondary)
                    } header: {
                        Text("Status")
                    }
                }

                Section {
                    HStack {
                        Text("ASLR:")

                        Spacer()

                        Text(isaslr ? "enabled" : "disabled")
                            .foregroundColor(isaslr ? .red : .green)
                            .monospaced()

                        Button {
                            isaslr = aslrstate
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Button("Toggle ASLR") {
                        toggleaslr()
                        isaslr = aslrstate
                    }
                } header: {
                    Text("ASLR")
                }

                Section {
                    Button("Respring") {
                        mgr.respring()
                    }

                    HStack {
                        Text("ourproc:")
                        Spacer()
                        Text(
                            mgr.dsready
                            ? String(format: "0x%llx", ds_get_our_proc())
                            : "N/A"
                        )
                        .monospaced()
                        .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("ourtask:")
                        Spacer()
                        Text(
                            mgr.dsready
                            ? String(format: "0x%llx", ds_get_our_task())
                            : "N/A"
                        )
                        .monospaced()
                        .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("UID:")
                        Spacer()
                        Text("\(uid)")
                            .monospaced()
                            .foregroundColor(.secondary)

                        Button {
                            uid = getuid()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    HStack {
                        Text("PID:")
                        Spacer()
                        Text("\(pid)")
                            .monospaced()
                            .foregroundColor(.secondary)

                        Button {
                            pid = getpid()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                } header: {
                    Text("Process")
                }

                Section {
                    HStack {
                        Text("Process:")
                        Spacer()
                        TextField("e.g. SpringBoard", text: $crashname)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .monospaced()
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Button("Crash") {
                        crashname.withCString { _ = crashproc($0) }
                    }
                    .disabled(crashname.isEmpty)

                    Button("Pause") {
                        crashname.withCString { _ = proc_pause_resume($0, false) }
                        pausedProcesses.insert(crashname)
                    }
                    .disabled(crashname.isEmpty || pausedProcesses.contains(crashname))

                    Button("Resume") {
                        crashname.withCString { _ = proc_pause_resume($0, true) }
                        pausedProcesses.remove(crashname)
                    }
                    .disabled(crashname.isEmpty || !pausedProcesses.contains(crashname))

                    Button("SBX Escape Helper") {
                        crashname.withCString { cstr in
                            proc_sbx = procbyname(cstr)
                        }

                        if proc_sbx == 0 {
                            status = "Failed to get proc"
                        }

                        let errorcheck = sbx_escape(proc_sbx)
                        status = errorcheck == 0 ? nil : "Failure!"
                    }
                    .disabled(crashname.isEmpty)
                } header: {
                    Text("Task Manager")
                }

                Section {
                    Button("Pocket Poster Helper") {
                        status = mgr.PPHelper()
                            ? "Succeeded. Open Pocket Poster settings."
                            : "Failed. Check logs."
                    }
                    .disabled(!mgr.sbxready)
                }

                Section {
                    Text(status ?? "No status")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tools")

            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .ignoresSafeArea(edges: .bottom)

            .alert("Status", isPresented: .constant(status != nil)) {
                Button("OK") { status = nil }
            } message: {
                Text(status ?? "")
            }

            .onAppear {
                if mgr.dsready {
                    getaslrstate()
                    isaslr = aslrstate
                }
            }
        }
    }
}
