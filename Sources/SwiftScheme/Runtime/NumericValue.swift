import Foundation
import SwiftSchemeNumeric

package func schemeNumberValue(_ value: Value) -> SchemeNumber? {
  switch value {
  case .integer(let value): SchemeNumber(value)
  case .rational(let value): SchemeNumber(value)
  case .real(let value): SchemeNumber(value)
  case .complex(let real, let imaginary): .complex(real: real, imaginary: imaginary)
  default: nil
  }
}
