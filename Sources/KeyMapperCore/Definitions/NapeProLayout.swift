import Foundation

/// The Keychron Nape Pro as it lies below a keyboard (Keychron's 90° setting): M1/M2 at the left end, 01/02, the ball
/// in its scroll ring, 03/04, then the end cap with the pairing button. Keychron's definition only gives a callout
/// point per button on a product picture, so the shapes are measured from that picture (412 × 1532 px, upright;
/// 1u = 100 px, turned a quarter clockwise).
enum NapeProLayout {
    /// The definition's button ids this drawing places; a device with any other id gets the generic button row.
    static let buttonIDs: Set<String> = ["01", "02", "03", "04", "m1", "m2"]

    static let body = DeviceBody(
        width: 15.32, height: 4.12, cornerRadius: 0.3,
        ball: .init(x: 7.67, y: 2.06, radius: 1.4),
        ring: .init(x: 7.67, y: 2.06, radius: 2.0),
        seams: [2.62, 12.77],
        buttons: [.init(x: 13.22, y: 3.5, radius: 0.27)]
    )

    /// Button frames by definition id, in the body's space.
    static let frames: [String: (x: Double, y: Double, w: Double, h: Double)] = [
        "m1": (0.32, 0.3, 2.0, 1.66), "m2": (0.32, 2.16, 2.0, 1.66),
        "01": (2.68, 0.06, 2.8, 2.0), "02": (2.68, 2.06, 2.8, 2.0),
        "03": (9.86, 0.06, 2.85, 2.0), "04": (9.86, 2.06, 2.85, 2.0),
    ]

    /// The two turning directions of the scroll ring, on its left (↺) and right (↻) edge.
    static func ringKeys(encoder: Int) -> [LayoutKey] {
        [LayoutKey(row: -1, col: -1, x: 5.53, y: 1.61, w: 0.66, h: 0.9, encoderIndex: encoder, encoderDirection: 0),
         LayoutKey(row: -1, col: -1, x: 9.15, y: 1.61, w: 0.66, h: 0.9, encoderIndex: encoder, encoderDirection: 1)]
    }

    /// The Nape Pro's keys from Keychron's button list, or nil when the list isn't the Nape Pro's.
    static func keys(_ entries: [[String: Any]], maxColumns: Int) -> [LayoutKey]? {
        var keys: [LayoutKey] = []
        var placed = Set<String>()
        var knobs = 0
        for entry in entries {
            guard let id = (entry["id"] as? String)?.lowercased() else { return nil }
            if entry["labels"] != nil {
                // One scroll ring; a second knob would be a different device.
                guard knobs == 0 else { return nil }
                keys += ringKeys(encoder: knobs)
                knobs += 1
                continue
            }
            guard let frame = frames[id], let col = DefinitionParser.int(entry["col"]), (0..<maxColumns).contains(col),
                  placed.insert(id).inserted else { return nil }
            keys.append(LayoutKey(row: 0, col: col, x: frame.x, y: frame.y, w: frame.w, h: frame.h, name: id.uppercased()))
        }
        return placed == buttonIDs && knobs == 1 ? keys : nil
    }
}
