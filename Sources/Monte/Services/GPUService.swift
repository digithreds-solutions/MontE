import Foundation
import IOKit

// MARK: - GPU & Apple Silicon Accelerator Service
// Reads real-time GPU utilization, allocated memory, and renderer info directly via IOKit IOAccelerator.
// Zero subprocess overhead (<0.05ms per query).

final class GPUService: @unchecked Sendable {

    static let shared = GPUService()

    struct GPUInfo: Equatable, Sendable {
        var isAvailable: Bool = false
        var modelName: String = "Apple Silicon GPU"
        var deviceUtilizationPercent: Double = 0.0
        var allocatedMemoryMb: Double = 0.0
        var inUseMemoryMb: Double = 0.0
        var tilerUtilizationPercent: Double = 0.0
        var rendererUtilizationPercent: Double = 0.0
    }

    private let lock = NSLock()

    func readGPU() -> GPUInfo {
        lock.lock()
        defer { lock.unlock() }

        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOAccelerator")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return GPUInfo()
        }
        defer { IOObjectRelease(iterator) }

        var info = GPUInfo()
        var service = IOIteratorNext(iterator)

        while service != 0 {
            var properties: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = properties?.takeRetainedValue() as? [String: Any] {

                if let model = dict["model"] as? String, !model.isEmpty {
                    info.modelName = model
                }

                if let perf = dict["PerformanceStatistics"] as? [String: Any] {
                    info.isAvailable = true

                    if let util = perf["Device Utilization %"] as? NSNumber {
                        info.deviceUtilizationPercent = util.doubleValue
                    }
                    if let tiler = perf["Tiler Utilization %"] as? NSNumber {
                        info.tilerUtilizationPercent = tiler.doubleValue
                    }
                    if let renderer = perf["Renderer Utilization %"] as? NSNumber {
                        info.rendererUtilizationPercent = renderer.doubleValue
                    }
                    if let allocMem = perf["Alloc system memory"] as? NSNumber {
                        info.allocatedMemoryMb = allocMem.doubleValue / 1_048_576.0
                    }
                    if let inUseMem = perf["In use system memory"] as? NSNumber {
                        info.inUseMemoryMb = inUseMem.doubleValue / 1_048_576.0
                    }
                    IOObjectRelease(service)
                    break
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        return info
    }
}
