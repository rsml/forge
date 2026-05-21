import Testing
@testable import ForgeCore

@Suite("ColorFGBG")
struct ColorFGBGTests {

    @Test("white background reports light")
    func whiteBackgroundReportsLight() {
        #expect(ColorFGBG.value(red: 1.0, green: 1.0, blue: 1.0) == "0;15")
    }

    @Test("black background reports dark")
    func blackBackgroundReportsDark() {
        #expect(ColorFGBG.value(red: 0.0, green: 0.0, blue: 0.0) == "15;0")
    }

    @Test("mid-luminance threshold splits at 0.5")
    func midLuminanceThreshold() {
        // Rec.601 luminance: 0.299r + 0.587g + 0.114b
        // Pure green at full = 0.587 → above 0.5 → light
        #expect(ColorFGBG.value(red: 0.0, green: 1.0, blue: 0.0) == "0;15")
        // Pure red at full = 0.299 → below 0.5 → dark
        #expect(ColorFGBG.value(red: 1.0, green: 0.0, blue: 0.0) == "15;0")
        // Pure blue at full = 0.114 → below 0.5 → dark
        #expect(ColorFGBG.value(red: 0.0, green: 0.0, blue: 1.0) == "15;0")
    }

    @Test("BackgroundLuminance agrees with ColorFGBG")
    func backgroundLuminanceConsistency() {
        #expect(BackgroundLuminance.isLight(red: 1.0, green: 1.0, blue: 1.0))
        #expect(!BackgroundLuminance.isLight(red: 0.0, green: 0.0, blue: 0.0))
        #expect(BackgroundLuminance.isLight(red: 0.0, green: 1.0, blue: 0.0))
        #expect(!BackgroundLuminance.isLight(red: 1.0, green: 0.0, blue: 0.0))
    }
}
