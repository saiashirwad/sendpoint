import Foundation
@testable import SendpointDomain

func filled(_ leading: [Stack]) -> [Stack] {
    leading + (leading.count..<StackDocument.stackCount).map { _ in Stack() }
}
