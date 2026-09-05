import Darwin
import Foundation

/// Only processes on the selected TTY, descended from the captured app, are
/// candidates. Foreground pipelines must agree on a directory; never guess by PID.
struct TerminalProcessSnapshot: Sendable {
    let pid: pid_t
    let parentPID: pid_t
    let processGroup: UInt32
    let foregroundGroup: UInt32
    let ttyDevice: UInt32
    let startedAtSeconds: UInt64
    let startedAtMicroseconds: UInt64
}

enum TerminalProcessSelection {
    static func foregroundProcesses(
        in processes: [TerminalProcessSnapshot], ttyDevice: UInt32, applicationPID: pid_t
    ) -> [TerminalProcessSnapshot] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        return processes.filter { process in
            guard process.ttyDevice == ttyDevice,
                  process.processGroup != 0,
                  process.processGroup == process.foregroundGroup else { return false }
            var ancestor = process.parentPID
            var visited: Set<pid_t> = [process.pid]
            while ancestor > 1, visited.insert(ancestor).inserted {
                if ancestor == applicationPID { return true }
                guard let parent = byPID[ancestor] else { return false }
                ancestor = parent.parentPID
            }
            return false
        }
    }

    static func agreedDirectory(_ directories: [URL?]) -> URL? {
        guard let first = directories.first, let directory = first,
              directories.allSatisfy({ $0 == directory }) else { return nil }
        return directory
    }
}

extension ProvenanceSystemBoundary {
    static func directoryForTTY(_ tty: String, applicationPID: pid_t) throws -> URL? {
        guard tty.hasPrefix("/dev/tty"), !tty.contains("\0"), !tty.dropFirst(5).contains("/") else { return nil }
        try Task.checkCancellation()
        var device = stat()
        guard lstat(tty, &device) == 0, (device.st_mode & S_IFMT) == S_IFCHR else { return nil }
        try Task.checkCancellation()
        let required = proc_listallpids(nil, 0)
        guard required > 0 else { return nil }
        var pids = [pid_t](repeating: 0, count: Int(required) + 128)
        let bytes = Int32(pids.count * MemoryLayout<pid_t>.stride)
        let count = proc_listallpids(&pids, bytes)
        try Task.checkCancellation()
        guard count > 0, count <= pids.count else { return nil }
        let processes = try pids.prefix(Int(count)).compactMap { try processSnapshot($0) }
        let candidates = TerminalProcessSelection.foregroundProcesses(
            in: processes, ttyDevice: UInt32(bitPattern: device.st_rdev), applicationPID: applicationPID
        )
        let directories: [URL?] = try candidates.map { candidate in
            try Task.checkCancellation()
            var info = proc_vnodepathinfo()
            let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
            guard proc_pidinfo(candidate.pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
            try Task.checkCancellation()
            // Reject PID reuse or a foreground-job change while reading the CWD.
            guard let current = try processSnapshot(candidate.pid),
                  current.startedAtSeconds == candidate.startedAtSeconds,
                  current.startedAtMicroseconds == candidate.startedAtMicroseconds,
                  current.parentPID == candidate.parentPID,
                  current.ttyDevice == candidate.ttyDevice,
                  current.processGroup == candidate.processGroup,
                  current.foregroundGroup == candidate.foregroundGroup else { return nil }
            let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { bytes in
                String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            }
            return LocalFileLocation.absolutePath(path)
        }
        try Task.checkCancellation()
        return TerminalProcessSelection.agreedDirectory(directories)
    }

    private static func processSnapshot(_ pid: pid_t) throws -> TerminalProcessSnapshot? {
        try Task.checkCancellation()
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let count = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
        try Task.checkCancellation()
        if count != size {
            // login runs as root. macOS exposes its ancestry through SHORTBSDINFO
            // even when the full BSD record is denied to an ordinary user.
            var parent = proc_bsdshortinfo()
            let parentSize = Int32(MemoryLayout<proc_bsdshortinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &parent, parentSize) == parentSize else { return nil }
            try Task.checkCancellation()
            return TerminalProcessSnapshot(
                pid: pid, parentPID: pid_t(parent.pbsi_ppid),
                processGroup: parent.pbsi_pgid, foregroundGroup: 0,
                ttyDevice: .max, startedAtSeconds: 0, startedAtMicroseconds: 0
            )
        }
        return TerminalProcessSnapshot(
            pid: pid, parentPID: pid_t(info.pbi_ppid),
            processGroup: info.pbi_pgid, foregroundGroup: info.e_tpgid,
            ttyDevice: info.e_tdev, startedAtSeconds: info.pbi_start_tvsec,
            startedAtMicroseconds: info.pbi_start_tvusec
        )
    }
}
