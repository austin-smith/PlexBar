@testable import PlexClientKit
import Foundation
import Testing
@testable import PlexBar

@Suite
struct PlexBoundedConcurrentMapTests {
    @Test func capsConcurrencyAndPreservesInputOrder() async {
        let probe = ConcurrentWorkProbe()

        let results = await PlexBoundedConcurrentMap.compactMap(
            Array(0..<12),
            maximumConcurrentTasks: 3
        ) { value in
            await probe.process(value)
        }

        #expect(results == [2, 4, 8, 10, 14, 16, 20, 22])
        #expect(await probe.maximumActiveTaskCount == 3)
    }

    @Test func normalizesAZeroLimitAndHandlesEmptyInput() async {
        let probe = ConcurrentWorkProbe()
        let results = await PlexBoundedConcurrentMap.compactMap(
            [1, 2, 3],
            maximumConcurrentTasks: 0
        ) { value in
            await probe.process(value)
        }
        let empty: [Int] = await PlexBoundedConcurrentMap.compactMap(
            [],
            maximumConcurrentTasks: 4
        ) { value in
            value
        }

        #expect(results == [2, 4])
        #expect(await probe.maximumActiveTaskCount == 1)
        #expect(empty.isEmpty)
    }
}

private actor ConcurrentWorkProbe {
    private var activeTaskCount = 0
    private(set) var maximumActiveTaskCount = 0

    func process(_ value: Int) async -> Int? {
        activeTaskCount += 1
        maximumActiveTaskCount = max(maximumActiveTaskCount, activeTaskCount)
        try? await Task.sleep(for: .milliseconds(10))
        activeTaskCount -= 1
        return value.isMultiple(of: 3) ? nil : value * 2
    }
}
