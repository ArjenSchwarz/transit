// DESIGN PROTOTYPE ONLY: not part of Transit app or production implementation.
import Foundation
import Dispatch

nonisolated final class Admission: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var generation = 0
    func reserve() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard count < 8 else { return false }
        count += 1
        return true
    }
    func finishPhysicalWork() { lock.lock(); count -= 1; lock.unlock() }
    func restart() { lock.lock(); generation += 1; lock.unlock() }
    func unfinished() -> Int { lock.lock(); defer { lock.unlock() }; return count }
}

nonisolated final class ResultGate: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Data?
    private var waiter: CheckedContinuation<Data, Never>?
    private(set) var published = false
    let deadline: UInt64
    let timeout: Data
    init(id: Int, admitted: UInt64) {
        // Reserve encoding/delivery headroom inside the five-second contract.
        deadline = admitted + 4_850_000_000
        timeout = Data("{\"jsonrpc\":\"2.0\",\"id\":\(id),\"result\":{\"isError\":true,\"content\":[{\"type\":\"text\",\"text\":\"READ_TIMEOUT\"}]}}".utf8)
    }
    func offer(_ bytes: Data, publish: Bool) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let inTime = DispatchTime.now().uptimeNanoseconds < deadline
        result = inTime ? bytes : timeout
        published = publish && inTime
        let saved = result!
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume(returning: saved)
    }
    func expire() { offer(timeout, publish: false) }
    @concurrent func value() async -> Data {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let saved = result { lock.unlock(); continuation.resume(returning: saved) }
            else { waiter = continuation; lock.unlock() }
        }
    }
    func didPublish() -> Bool { lock.lock(); defer { lock.unlock() }; return published }
}

@MainActor func nonCooperativeCapture(id: Int, gate: ResultGate) {
    if id == 0 { Thread.sleep(forTimeInterval: 6.0) }
    gate.offer(Data("{\"result\":\"captured\"}".utf8), publish: true)
}

@concurrent nonisolated func runProbe() async {
    let admission = Admission()
    let timers = DispatchQueue(label: "t63.design.deadline", qos: .userInitiated, attributes: .concurrent)
    let start = DispatchTime.now().uptimeNanoseconds
    var gates: [ResultGate] = []
    var sources: [DispatchSourceTimer] = []
    for id in 0..<8 {
        precondition(admission.reserve())
        let gate = ResultGate(id: id, admitted: start)
        gates.append(gate)
        let source = DispatchSource.makeTimerSource(flags: .strict, queue: timers)
        source.setEventHandler { gate.expire() }
        source.schedule(deadline: DispatchTime(uptimeNanoseconds: gate.deadline), leeway: .nanoseconds(0))
        source.resume()
        sources.append(source)
        Task.detached {
            await nonCooperativeCapture(id: id, gate: gate)
            admission.finishPhysicalWork()
        }
        // Ensure the blocked read enters MainActor before scheduling queued reads.
        if id == 0 { try! await Task.sleep(for: .milliseconds(100)) }
    }
    admission.restart()
    precondition(!admission.reserve(), "restart must not reset physical capacity")
    var times: [Double] = []
    var responses: [Data] = []
    for gate in gates {
        responses.append(await gate.value())
        times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
    }
    let encodedBatch = Data(([UInt8]("[".utf8) + responses.enumerated().flatMap {
        ($0.offset == 0 ? [] : [UInt8](",".utf8)) + [UInt8]($0.element)
    } + [UInt8]("]".utf8)))
    precondition((try! JSONSerialization.jsonObject(with: encodedBatch)) is [Any])
    let batchMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    let unfinishedAtTimeout = admission.unfinished()
    sources.forEach { $0.cancel() }
    FileHandle.standardOutput.write(Data("MEASURE batch_ms=\(batchMs) response_ms=\(times) unfinished=\(unfinishedAtTimeout)\n".utf8))
    precondition(times.max()! < 5_000 && batchMs < 5_000)
    precondition(unfinishedAtTimeout == 8, "timed-out work must retain its slots")
    precondition(gates.allSatisfy { !$0.didPublish() })
    try! await Task.sleep(for: .milliseconds(1_500))
    precondition(admission.unfinished() == 0)
    precondition(gates.allSatisfy { !$0.didPublish() }, "late capture must not publish")
    print("PASS blocked_mainactor_ms=6000 encoded_batch_ms=\(String(format: "%.2f", batchMs)) max_response_ms=\(String(format: "%.2f", times.max()!)) unfinished_at_timeout=\(unfinishedAtTimeout) unfinished_after_completion=\(admission.unfinished()) late_publications=0 restart_busy=true bytes=\(encodedBatch.count)")
}

@main struct Probe {
    static func main() async {
        // Detached driver is independent of the deliberately blocked MainActor.
        await Task.detached { await runProbe() }.value
    }
}
