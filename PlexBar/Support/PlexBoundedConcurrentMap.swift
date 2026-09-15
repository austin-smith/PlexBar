import Foundation

enum PlexBoundedConcurrentMap {
    static func compactMap<Input: Sendable, Output: Sendable>(
        _ inputs: [Input],
        maximumConcurrentTasks: Int,
        transform: @escaping @Sendable (Input) async -> Output?
    ) async -> [Output] {
        guard !inputs.isEmpty else { return [] }

        let taskLimit = min(max(maximumConcurrentTasks, 1), inputs.count)
        return await withTaskGroup(
            of: (index: Int, output: Output?).self,
            returning: [Output].self
        ) { group in
            for index in 0..<taskLimit {
                group.addTask {
                    (index, await transform(inputs[index]))
                }
            }

            var nextIndex = taskLimit
            var orderedResults = [Output?](repeating: nil, count: inputs.count)
            while let result = await group.next() {
                orderedResults[result.index] = result.output

                guard !Task.isCancelled else {
                    group.cancelAll()
                    continue
                }
                if nextIndex < inputs.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask {
                        (index, await transform(inputs[index]))
                    }
                }
            }
            return orderedResults.compactMap { $0 }
        }
    }
}
