import Foundation
import SwiftyH3

/// Canonical H3 cell encoding for JSON/SQLite wire formats.
///
/// Rules:
/// - Cells are **lowercase hexadecimal strings** only (never JSON integers).
/// - Every `h3Cells` array must be paired with an explicit `h3Resolution` at the model layer.
/// - This type performs normalization/validation only; no geocoding or ranking.
public enum ExchangeH3Codec: Sendable {
  public static let minResolution = 0
  public static let maxResolution = 15
  public static let maxCellsPerSet = 128

  private static let cellPattern = try! NSRegularExpression(pattern: #"^[0-9a-f]{15}$"#)

  /// Normalizes a single cell to lowercase hex, or nil if empty/invalid shape.
  public static func normalizeCellString(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let lowered = trimmed.lowercased()
    guard matchesCellShape(lowered) else { return nil }
    return lowered
  }

  /// Normalizes many cells: lowercase, shape filter, dedupe, cap count.
  public static func normalizeCells(_ raw: [String], maxCount: Int = maxCellsPerSet) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for value in raw {
      guard let normalized = normalizeCellString(value) else { continue }
      guard !seen.contains(normalized) else { continue }
      seen.insert(normalized)
      out.append(normalized)
      if out.count >= maxCount { break }
    }
    return out
  }

  /// True when the string is a valid H3 cell index (after normalization).
  public static func validateCellString(_ raw: String) -> Bool {
    guard let normalized = normalizeCellString(raw) else { return false }
    return isValidH3Cell(normalized)
  }

  /// Validates every cell and optionally checks resolution consistency.
  public static func validateCells(_ raw: [String], resolution expectedResolution: Int?) -> Bool {
    var normalized: [String] = []
    normalized.reserveCapacity(raw.count)

    for value in raw {
      guard let cell = normalizeCellString(value), isValidH3Cell(cell) else { return false }
      normalized.append(cell)
    }
    guard !normalized.isEmpty else { return false }

    var resolved: Int?
    for cell in normalized {
      guard let cellRes = cellResolution(cell) else { return false }
      if let existing = resolved {
        guard existing == cellRes else { return false }
      } else {
        resolved = cellRes
      }
    }

    if let expectedResolution {
      guard let resolved, resolved == expectedResolution else { return false }
    }
    return true
  }

  /// Returns H3 resolution for a normalized cell string, or nil if invalid.
  public static func cellResolution(_ normalizedCell: String) -> Int? {
    guard let normalized = normalizeCellString(normalizedCell), isValidH3Cell(normalized) else {
      return nil
    }
    guard let cell = H3Cell(normalized) else { return nil }
    guard let resolution = try? cell.resolution else { return nil }
    return Int(resolution.rawValue)
  }

  // MARK: - Private

  private static func matchesCellShape(_ value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return cellPattern.firstMatch(in: value, options: [], range: range) != nil
  }

  private static func isValidH3Cell(_ normalized: String) -> Bool {
    guard let cell = H3Cell(normalized) else { return false }
    return cell.isValid
  }
}
