import Foundation
import Testing
@testable import KeyMapperCore

/// Pixel-for-pixel parity with AMG65 Studio's renderer.py, whose frames run on the user's keyboard.
/// `Fixtures/led-golden.json` was produced by running Studio's own renderer with the inputs stored in it.
@Suite struct LEDMatrixRendererTests {
    private func golden() throws -> [String: Any] {
        let url = try #require(Bundle.module.url(forResource: "led-golden", withExtension: "json", subdirectory: "Fixtures"))
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func hex(_ frame: [RGB24]) -> String { frame.map { String(format: "%02x%02x%02x", $0.r, $0.g, $0.b) }.joined() }

    private func quota(_ row: [String: Any]) -> LEDQuota {
        LEDQuota(provider: row["id"] as! String, remainingPercent: (row["remaining_percent"] as? NSNumber)?.doubleValue,
                 stale: row["stale"] as? Bool ?? false)
    }

    private func frame(_ hex: String) -> [RGB24] {
        let bytes = stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
        return stride(from: 0, to: bytes.count, by: 3).map { RGB24(r: bytes[$0], g: bytes[$0 + 1], b: bytes[$0 + 2]) }
    }

    private func activity(_ row: [String: Any]) -> LEDActivity {
        LEDActivity(provider: row["provider"] as! String, state: row["state"] as! String, summary: row["summary"] as? String,
                    expiresAt: (row["expires_at"] as? NSNumber)?.doubleValue ?? .infinity, stale: row["stale"] as? Bool ?? false)
    }

    private static let quotas = [LEDQuota(provider: "claude", remainingPercent: 80, stale: false),
                                 LEDQuota(provider: "codex", remainingPercent: 45.6, stale: true),
                                 LEDQuota(provider: "cursor", remainingPercent: nil, stale: false)]
    private static let fullQuotas = [LEDQuota(provider: "claude", remainingPercent: 0, stale: false),
                                     LEDQuota(provider: "codex", remainingPercent: 100, stale: false),
                                     LEDQuota(provider: "cursor", remainingPercent: 12.5, stale: false)]

    @Test func overviewAndDetailMatchStudio() throws {
        let g = try golden()
        for case let item as [String: Any] in g["overview"] as! [Any] {
            let quotas = (item["snapshot"] as! [[String: Any]]).map(quota)
            let frame = LEDMatrixRenderer.overview(quotas, brightness: item["brightness"] as! Double, claudeGreenGain: item["gain"] as! Double)
            #expect(hex(frame) == item["frame"] as? String)
        }
        for case let item as [String: Any] in g["detail"] as! [Any] {
            let frame = LEDMatrixRenderer.detail(quota(item["quota"] as! [String: Any]), brightness: item["brightness"] as! Double,
                                                 claudeGreenGain: item["gain"] as! Double)
            #expect(hex(frame) == item["frame"] as? String)
        }
    }

    @Test func textAndEffectsMatchStudio() throws {
        let g = try golden()
        for case let item as [String: Any] in g["text"] as! [Any] {
            let color = try #require(RGB24(hex: item["color"] as! String))
            let frame = LEDMatrixRenderer.text(item["text"] as! String, color: color, brightness: item["brightness"] as! Double,
                                               elapsed: (item["elapsed"] as! NSNumber).doubleValue, marquee: item["marquee"] as! Bool)
            #expect(hex(frame) == item["frame"] as? String, "\(item["text"]!)")
        }
        let base = frame(g["effectsBase"] as! String)
        for case let item as [String: Any] in g["effects"] as! [Any] {
            let effect = try #require(LEDTextEffect(rawValue: item["effect"] as! String))
            let result = LEDMatrixRenderer.applyTextEffect(base, effect: effect, brightness: item["brightness"] as! Double,
                                                           elapsed: (item["elapsed"] as! NSNumber).doubleValue, left: item["left"] as! Int)
            #expect(hex(result) == item["frame"] as? String, "\(effect) at \(item["elapsed"]!)s from \(item["left"]!)")
        }
    }

    @Test func activityAndMascotMatchStudio() throws {
        let g = try golden()
        for case let item as [String: Any] in g["activity"] as! [Any] {
            let frame = LEDMatrixRenderer.activity(activity(item["activity"] as! [String: Any]), quotas: Self.quotas, brightness: 0.5,
                                                   elapsed: (item["elapsed"] as! NSNumber).doubleValue, claudeGreenGain: 0.8)
            #expect(hex(frame) == item["frame"] as? String)
        }
        for case let item as [String: Any] in g["mascot"] as! [Any] {
            let act = activity(item["activity"] as! [String: Any])
            let frame = LEDMatrixRenderer.mascot(act, quotas: Self.fullQuotas, brightness: 0.45,
                                                 elapsed: (item["elapsed"] as! NSNumber).doubleValue, claudeGreenGain: 0.9)
            #expect(hex(frame) == item["frame"] as? String, "\(act.provider) \(act.state) at \(item["elapsed"]!)s")
        }
    }

    @Test func activitySelectionMatchesStudio() throws {
        let g = try golden()
        let sets = g["selectRows"] as! [String: [[String: Any]]]
        for case let item as [String: Any] in g["select"] as! [Any] {
            let rows = sets[item["rows"] as! String]!.map(activity)
            let selected = LEDMatrixRenderer.selectActivity(rows, elapsed: (item["elapsed"] as! NSNumber).doubleValue, now: 1000,
                                                            provider: item["provider"] as! String)
            #expect(selected.map { "\($0.provider):\($0.state)" } == item["selected"] as? String,
                    "\(item["rows"]!) at \(item["elapsed"]!)s for \(item["provider"]!)")
        }
    }

    @Test func pythonRoundingIsKept() {
        #expect(LEDMatrixRenderer.pyRound(80.5) == 80)
        #expect(LEDMatrixRenderer.pyRound(2.5) == 2)
        #expect(LEDMatrixRenderer.pyRound(3.5) == 4)
        #expect(LEDMatrixRenderer.pyMod(-7, 5) == 3)
    }
}
