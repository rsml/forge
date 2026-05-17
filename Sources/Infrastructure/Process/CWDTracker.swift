import Foundation
import Darwin

enum CWDTracker {
    static func currentWorkingDirectory(pid: pid_t) -> String? {
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let pathInfo = UnsafeMutablePointer<proc_vnodepathinfo>.allocate(capacity: 1)
        defer { pathInfo.deallocate() }
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, pathInfo, Int32(size))
        guard ret == size else { return nil }
        return withUnsafePointer(to: &pathInfo.pointee.pvi_cdir.vip_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cPath in
                String(cString: cPath)
            }
        }
    }
}
