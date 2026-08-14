import Foundation

package func makeList<S: Sequence>(_ values: S, tail: Value = .empty) -> Value
where S.Element == Value { Array(values).reversed().reduce(tail) { .pair(Pair($1, $0)) } }
