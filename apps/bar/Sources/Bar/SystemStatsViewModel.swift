import Darwin
import Foundation
import IOKit

/// CPU / GPU / memory utilization for the status bar pills.
@MainActor
final class SystemStatsViewModel: ObservableObject {
    @Published private(set) var cpuPercent: Int = 0
    @Published private(set) var gpuPercent: Int = 0
    @Published private(set) var memoryPercent: Int = 0

    private var timer: Timer?
    private var previousCPU: host_cpu_load_info?
    private var sampleGeneration: UInt64 = 0

    var cpuLabel: String { "\(cpuPercent)%" }
    var gpuLabel: String { "\(gpuPercent)%" }
    var memoryLabel: String { "\(memoryPercent)%" }

    func start() {
        stop()
        refresh()
        // 5s is enough for a status pill; sampling runs off the main thread.
        let timer = Timer(timeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        timer.tolerance = 1.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sampleGeneration &+= 1
        previousCPU = nil
    }

    func refresh() {
        sampleGeneration &+= 1
        let generation = sampleGeneration
        let previous = previousCPU
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cpu = Self.sampleCPU(previous: previous)
            let mem = Self.sampleMemoryPercent()
            let gpu = Self.sampleGPUPercent()
            DispatchQueue.main.async {
                guard let self, generation == self.sampleGeneration else { return }
                if let cpu {
                    self.previousCPU = cpu.load
                    if self.cpuPercent != cpu.percent {
                        self.cpuPercent = cpu.percent
                    }
                }
                if self.memoryPercent != mem {
                    self.memoryPercent = mem
                }
                if self.gpuPercent != gpu {
                    self.gpuPercent = gpu
                }
            }
        }
    }

    // MARK: - CPU

    private struct CPUSample {
        let load: host_cpu_load_info
        let percent: Int
    }

    private static func sampleCPU(previous: host_cpu_load_info?) -> CPUSample? {
        guard let current = hostCPULoadInfo() else { return nil }
        guard let previous else {
            return CPUSample(load: current, percent: 0)
        }

        let user = Double(current.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(current.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(current.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(current.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else {
            return CPUSample(load: current, percent: 0)
        }
        let busy = (user + system + nice) / total * 100
        let percent = Int(busy.rounded())
        return CPUSample(load: current, percent: min(max(percent, 0), 100))
    }

    private static func hostCPULoadInfo() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withHostPort { host in
            withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
                }
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    // MARK: - Memory

    private static func sampleMemoryPercent() -> Int {
        guard let vm = vmStatistics64() else { return 0 }

        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &size, nil, 0) == 0, total > 0 else {
            return 0
        }

        let page = UInt64(vm_kernel_page_size)
        // Activity Monitor–style “used”: active+wired+compressed (+inactive/speculative
        // adjustments matching common macOS status tools).
        let positive =
            UInt64(vm.active_count)
            + UInt64(vm.inactive_count)
            + UInt64(vm.wire_count)
            + UInt64(vm.speculative_count)
            + UInt64(vm.compressor_page_count)
        let subtract = UInt64(vm.purgeable_count) + UInt64(vm.external_page_count)
        // Saturating subtract — UInt64 wrap would report ~100% used incorrectly.
        let usedPages = positive > subtract ? positive - subtract : 0
        let used = page * usedPages
        let percent = Int((Double(used) / Double(total) * 100).rounded())
        return min(max(percent, 0), 100)
    }

    private static func vmStatistics64() -> vm_statistics64? {
        var info = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withHostPort { host in
            withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(host, HOST_VM_INFO64, $0, &count)
                }
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info
    }

    /// `mach_host_self()` returns a send right that must be deallocated.
    private static func withHostPort<T>(_ body: (mach_port_t) -> T) -> T {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        return body(host)
    }

    // MARK: - GPU

    /// Reads IOAccelerator `Device Utilization %` (same source as Activity Monitor).
    private static func sampleGPUPercent() -> Int {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"),
            &iterator
        ) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var best = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var propsRef: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let props = propsRef?.takeRetainedValue() as? [String: Any]
            else { continue }

            if let perf = props["PerformanceStatistics"] as? [String: Any],
               let util = Self.intValue(perf["Device Utilization %"]) {
                best = max(best, util)
            } else if let util = Self.intValue(props["Device Utilization %"]) {
                best = max(best, util)
            }
        }
        return min(max(best, 0), 100)
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let n as Int: return n
        case let n as NSNumber: return n.intValue
        case let n as Double: return Int(n.rounded())
        default: return nil
        }
    }
}
