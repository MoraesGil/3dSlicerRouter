import Foundation
import IOKit

/// Admission for automatic geometry work. Cheap cached and embedded images bypass it.
enum PreviewGate {
    struct Busy: LocalizedError {
        var errorDescription: String? {
            L10n.t("Prévia 3D adiada. Tente novamente quando o Mac estiver livre.",
                   "3D preview deferred. Try again when the Mac is available.")
        }
    }

    static func permits(cpu: Double?, gpu: Double?, idle: Double, available: Double,
                        thermal: ProcessInfo.ThermalState, lowPower: Bool) -> Bool {
        guard let cpu, cpu < 30, available >= 0.25, !lowPower, thermal.rawValue < ProcessInfo.ThermalState.serious.rawValue else { return false }
        // Some Intel drivers and extension sandboxes do not expose GPU counters.
        return gpu.map { $0 < 30 } ?? (idle >= 180)
    }

    static func idleSeconds() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }
        let value = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString, nil, 0)?.takeRetainedValue()
        return ((value as? NSNumber)?.doubleValue ?? 0) / 1e9
    }

    private static func gpuPercent() -> Double? {
        var entries: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &entries) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(entries) }
        var peak: Double?
        while case let entry = IOIteratorNext(entries), entry != 0 {
            defer { IOObjectRelease(entry) }
            let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, nil, 0)?.takeRetainedValue() as? NSDictionary
            guard let number = stats?["Device Utilization %"] as? NSNumber else { continue }
            peak = max(peak ?? 0, number.doubleValue)
        }
        return peak
    }

    private static func cpuTicks() -> (UInt32, UInt32)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        let (user, system, idle, nice) = info.cpu_ticks
        return result == KERN_SUCCESS ? (user &+ system &+ nice, idle) : nil
    }

    private static func availableBytes() -> Double {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: vm) / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return (Double(vm.free_count) + Double(vm.inactive_count)) * Double(vm_kernel_page_size)
    }

    static func check(reserving bytes: Double = 0) throws {
        guard let first = cpuTicks() else { throw Busy() }
        Thread.sleep(forTimeInterval: 0.12)
        guard let last = cpuTicks() else { throw Busy() }
        let busy = Double(last.0 &- first.0)
        let total = busy + Double(last.1 &- first.1)
        let gpu = gpuPercent()
        guard permits(cpu: total > 0 ? 100 * busy / total : nil, gpu: gpu,
                      idle: gpu == nil ? idleSeconds() : 0, available: (availableBytes() - bytes) / Double(ProcessInfo.processInfo.physicalMemory),
                      thermal: ProcessInfo.processInfo.thermalState,
                      lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled) else { throw Busy() }
    }

    // One advisory lock per user, shared across installations and Quick Look containers.
    // Only this empty file needs write access. The kernel releases the lock on exit.
    static func withSlot<T>(at file: URL, _ body: () throws -> T) throws -> T {
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw Busy() }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw Busy() }
        return try body()
    }

    // Estimate working memory before inflation. XML, parsed buffers and the display geometry
    // can coexist. Later checkpoints use observed memory so the estimate is not counted twice.
    static func estimatedBytes(for url: URL) throws -> Double {
        if url.pathExtension.lowercased() == "gcode" {
            return Double(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) * 4
        }
        let zip = try ZipArchive(url: url)
        let modelBytes = zip.entries.reduce(0.0) { total, entry in
            total + (entry.key.lowercased().hasSuffix(".model") ? Double(entry.value.size) : 0)
        }
        return modelBytes * 3
    }

    static func run<T>(for url: URL, _ body: (_ checkpoint: @escaping () throws -> Void) throws -> T) throws -> T {
        let support = PreviewCache.directory.deletingLastPathComponent().deletingLastPathComponent()
        let slot = support.appendingPathComponent("com.moraesdev.3dslicerrouter.render-slot")
        return try withSlot(at: slot) {
            try check(reserving: try estimatedBytes(for: url))
            var next = ProcessInfo.processInfo.systemUptime + 2
            return try body {
                if ProcessInfo.processInfo.systemUptime >= next {
                    try check()
                    next = ProcessInfo.processInfo.systemUptime + 2
                }
            }
        }
    }
}
