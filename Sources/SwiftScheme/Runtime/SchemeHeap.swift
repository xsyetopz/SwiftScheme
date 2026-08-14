import Foundation

package protocol SchemeHeapNode: AnyObject {
  func traceSchemeChildren(_ visit: (any SchemeHeapNode) -> Void)
  func breakSchemeCycles()
}

private final class WeakSchemeNode {
  weak var value: (any SchemeHeapNode)?
  init(_ value: any SchemeHeapNode) { self.value = value }
}

public struct HeapStatistics: Equatable, Sendable {
  public let allocated: Int
  public let registered: Int
  public let live: Int
  public let collected: Int
}

package final class SchemeHeap {
  package init() {}
  private static let threadKey = "SwiftScheme.activeHeap"
  private var nodes: [ObjectIdentifier: WeakSchemeNode] = [:]
  private(set) var allocated = 0
  private(set) var collected = 0

  static var active: SchemeHeap? { Thread.current.threadDictionary[threadKey] as? SchemeHeap }

  package func withActive<T>(_ body: () throws -> T) rethrows -> T {
    let dictionary = Thread.current.threadDictionary
    let previous = dictionary[Self.threadKey]
    dictionary[Self.threadKey] = self
    defer {
      if let previous {
        dictionary[Self.threadKey] = previous
      } else {
        dictionary.removeObject(forKey: Self.threadKey)
      }
    }
    return try body()
  }

  package func register(_ node: any SchemeHeapNode) {
    let identifier = ObjectIdentifier(node)
    guard nodes[identifier]?.value == nil else { return }
    nodes[identifier] = WeakSchemeNode(node)
    allocated += 1
  }

  @discardableResult package func collect(roots: [any SchemeHeapNode]) -> HeapStatistics {
    nodes = nodes.filter { $0.value.value != nil }
    var marked = Set<ObjectIdentifier>()
    var pending = roots
    while let node = pending.popLast() {
      let identifier = ObjectIdentifier(node)
      guard marked.insert(identifier).inserted else { continue }
      node.traceSchemeChildren { pending.append($0) }
    }
    let unreachable = nodes.compactMap {
      identifier,
      weakNode -> (ObjectIdentifier, any SchemeHeapNode)? in
      guard !marked.contains(identifier), let node = weakNode.value else { return nil }
      return (identifier, node)
    }
    for (_, node) in unreachable { node.breakSchemeCycles() }
    collected += unreachable.count
    let removed = Set(unreachable.map(\.0))
    nodes = nodes.filter { !removed.contains($0.key) && $0.value.value != nil }
    return statistics
  }

  package var statistics: HeapStatistics {
    nodes = nodes.filter { $0.value.value != nil }
    return HeapStatistics(
      allocated: allocated,
      registered: nodes.count,
      live: nodes.values.reduce(0) { $0 + ($1.value == nil ? 0 : 1) },
      collected: collected
    )
  }
}

@inline(__always) package func registerSchemeNode(_ node: any SchemeHeapNode) {
  SchemeHeap.active?.register(node)
}
