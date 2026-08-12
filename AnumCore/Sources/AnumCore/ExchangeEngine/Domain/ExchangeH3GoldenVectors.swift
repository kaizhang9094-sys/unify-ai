import Foundation

/// Shared cross-platform H3 golden vectors (Swift ↔ Node parity checks).
public enum ExchangeH3GoldenVectors: Sendable {
  public static let latitudeDegrees = 37.3615593
  public static let longitudeDegrees = -122.0553238
  public static let resolution = 7
  /// `latLngToCell(37.3615593, -122.0553238, 7)` — h3-js / H3 4.4.x reference.
  public static let expectedCell = "87283472bffffff"
}
