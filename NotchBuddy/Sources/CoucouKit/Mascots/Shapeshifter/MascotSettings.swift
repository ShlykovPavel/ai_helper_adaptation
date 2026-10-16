import Foundation

public struct MascotSettings {
    public static let selectedMascotKey = "selectedMascot"
    public static let mascotShapeKey = "mascotShape"

    public static var selectedMascot: MascotType {
        get {
            guard let raw = UserDefaults.standard.string(forKey: selectedMascotKey),
                  let type = MascotType(rawValue: raw) else {
                return .shapeshifter
            }
            return type
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: selectedMascotKey)
        }
    }

    public static var shape: MascotShape {
        get {
            guard let raw = UserDefaults.standard.string(forKey: mascotShapeKey),
                  let shape = MascotShape(rawValue: raw) else {
                return .squircle
            }
            return shape
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: mascotShapeKey)
        }
    }
}
