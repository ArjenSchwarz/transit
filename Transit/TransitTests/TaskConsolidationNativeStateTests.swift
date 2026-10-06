import Foundation
import Testing
@testable import Transit

@MainActor struct TaskConsolidationNativeStateTests {
    @Test func unavailableCannotPublishAnotherTask() async {
        let state = TaskConsolidationNativeState()
        let source = UUID(), other = UUID()
        await state.refresh(source: source) { _ in
            TaskConsolidationNativeObservation(taskId: other, history: [], tasks: [], problem: nil)
        }
        #expect(state.observation == nil)
        #expect(state.problem != nil)
    }

    @Test func switchingIdentityInvalidatesBeforeWaiting() async {
        let state = TaskConsolidationNativeState()
        let first = UUID(), second = UUID()
        await state.refresh(source: first) { id in
            TaskConsolidationNativeObservation(taskId: id, history: [], tasks: [], problem: nil)
        }
        #expect(state.observation?.taskId == first)
        await state.refresh(source: second, wait: {
            #expect(state.observation == nil)
            #expect(state.sourceID == second)
        }, provider: { id in TaskConsolidationNativeObservation(taskId: id, history: [], tasks: [], problem: nil) })
        #expect(state.observation?.taskId == second)
    }
    @Test func cancelledCaptureCannotPublishAfterPhysicalCompletion() async throws {
        let state = TaskConsolidationNativeState(), latch = NativeHistoryLatch(), id = UUID()
        let job = Task {
            await state.refresh(source: id) { selected in
                await latch.wait()
                return TaskConsolidationNativeObservation(taskId: selected, history: [], tasks: [], problem: nil)
            }
        }
        for _ in 0..<100 where !(await latch.started) { await Task.yield() }
        try #require(await latch.started)
        job.cancel()
        await latch.release()
        await job.value
        #expect(state.observation == nil)
    }

    @Test func earlierGenerationCannotOverwriteNewSource() async throws {
        let state = TaskConsolidationNativeState(), latch = NativeHistoryLatch()
        let old = UUID(), current = UUID()
        let job = Task {
            await state.refresh(source: old) { selected in
                await latch.wait()
                return TaskConsolidationNativeObservation(taskId: selected, history: [], tasks: [], problem: nil)
            }
        }
        for _ in 0..<100 where !(await latch.started) { await Task.yield() }
        try #require(await latch.started)
        await state.refresh(source: current) { selected in
            TaskConsolidationNativeObservation(taskId: selected, history: [], tasks: [], problem: nil)
        }
        await latch.release()
        await job.value
        #expect(state.observation?.taskId == current)
    }

}

private actor NativeHistoryLatch {
    private(set) var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        started = true
        await withCheckedContinuation { waiter = $0 }
    }
    func release() {
        waiter?.resume()
        waiter = nil
    }
}
