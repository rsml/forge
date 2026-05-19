import Testing
import Foundation
@testable import ForgeCore

struct PortDetectorTests {
    @Test("detects localhost:5173 in vite output")
    func testVite() {
        let out = """
        VITE v5.0.0  ready in 84 ms
        ➜  Local:   http://localhost:5173/
        ➜  Network: use --host to expose
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.host == "localhost" && $0.port == 5173 })
    }

    @Test("detects npm ready-on port via 'ready on :3000' pattern")
    func testNpmReadyOn() {
        let out = "ready - started server on 0.0.0.0:3000, url: http://localhost:3000"
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 3000 })
    }

    @Test("ignores timestamps like 12:34:56")
    func testTimestampNoise() {
        let out = "[12:34:56] some log line\n[09:12:34] another"
        let ports = PortDetector.detect(in: out)
        #expect(ports.isEmpty)
    }

    @Test("deduplicates repeated ports")
    func testDedup() {
        let out = """
        ready on http://localhost:3000
        listening on http://localhost:3000
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.filter { $0.port == 3000 }.count == 1)
    }

    @Test("preserves first-seen order")
    func testOrder() {
        let out = """
        backend ready on :8080
        frontend ready on :3000
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.map(\.port) == [8080, 3000])
    }

    @Test("handles 127.0.0.1 and 0.0.0.0")
    func testAlternateHosts() {
        let out = """
        Listening on 127.0.0.1:4000
        Bound to 0.0.0.0:8000
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.host == "127.0.0.1" && $0.port == 4000 })
        #expect(ports.contains { $0.host == "0.0.0.0" && $0.port == 8000 })
    }

    @Test("rejects out-of-range ports")
    func testInvalidRanges() {
        // Port 70000 is invalid (max 65535)
        let out = "weird message localhost:70000"
        let ports = PortDetector.detect(in: out)
        #expect(ports.filter { $0.port == 70000 }.isEmpty)
    }

    @Test("empty input returns empty array")
    func testEmpty() {
        let ports = PortDetector.detect(in: "")
        #expect(ports.isEmpty)
    }

    // MARK: - port-keyword regex (port/server + space + digits)

    @Test("detects `port 8080` (Python http.server style)")
    func testPortKeywordSpace() {
        let out = "Serving HTTP on :: port 8080 (http://[::]:8080/) ..."
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 8080 && $0.host == "localhost" })
    }

    @Test("detects `server 8080`")
    func testServerKeywordSpace() {
        let out = "starting server 8080"
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 8080 })
    }

    @Test("detects `port: 8080` (colon + space)")
    func testPortKeywordColonSpace() {
        let out = "Listening on port: 8080"
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 8080 })
    }

    @Test("port-keyword regex catches short ports like 80")
    func testPortKeywordShortPort() {
        let out = "running on port 80"
        let ports = PortDetector.detect(in: out)
        #expect(ports.contains { $0.port == 80 })
    }

    @Test("port-keyword does not match unrelated digits")
    func testPortKeywordNoFalsePositive() {
        // "port" must be followed by whitespace and digits — not part of another word
        let out = "important 12345 things"
        let ports = PortDetector.detect(in: out)
        #expect(ports.isEmpty)
    }

    @Test("port-keyword dedups against strict pass")
    func testPortKeywordDedup() {
        // "port 3000" + "localhost:3000" should yield ONE result, not two
        let out = """
        listening on localhost:3000
        port 3000 ready
        """
        let ports = PortDetector.detect(in: out)
        #expect(ports.filter { $0.port == 3000 }.count == 1)
    }
}
