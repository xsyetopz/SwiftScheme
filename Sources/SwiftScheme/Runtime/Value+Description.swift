import Foundation

extension Value: CustomStringConvertible {
  /// Returns the same external representation as `written`.
  public var description: String { written }
}
