import Combine
import Darwin
import Foundation

struct ProcessResourceSnapshot {
    var cpuPercent: Double = 0
    var memoryBytes: UInt64 = 0
    var sampledAt: Date = .now
}

@MainActor
final class ProcessResourceMonitor: ObservableObject {
    @Published private(set) var snapshot = ProcessResourceSnapshot()

    private var timer: Timer?
    private var lastCPUSeconds: TimeInterval?
    private var lastWallTime: TimeInterval?

    func start() {
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastCPUSeconds = nil
        lastWallTime = nil
    }

    private func sample() {
        let now = ProcessInfo.processInfo.systemUptime
        let cpuSeconds = Self.processCPUSeconds()
        let memoryBytes = Self.residentMemoryBytes()

        var cpuPercent = snapshot.cpuPercent
        if let cpuSeconds, let lastCPUSeconds, let lastWallTime {
            let wallDelta = max(now - lastWallTime, 0.001)
            let cpuDelta = max(cpuSeconds - lastCPUSeconds, 0)
            cpuPercent = cpuDelta / wallDelta * 100.0
        } else if cpuSeconds != nil {
            cpuPercent = 0
        }

        if let cpuSeconds {
            lastCPUSeconds = cpuSeconds
            lastWallTime = now
        }

        snapshot = ProcessResourceSnapshot(
            cpuPercent: cpuPercent,
            memoryBytes: memoryBytes,
            sampledAt: .now
        )
    }

    private static func processCPUSeconds() -> TimeInterval? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        return seconds(from: usage.ru_utime) + seconds(from: usage.ru_stime)
    }

    private static func seconds(from value: timeval) -> TimeInterval {
        TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000.0
    }

    private static func residentMemoryBytes() -> UInt64 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else { return 0 }
        return UInt64(info.resident_size)
    }
}
