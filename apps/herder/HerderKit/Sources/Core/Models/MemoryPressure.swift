/// How hard the system is working to find memory, as the kernel reports it.
public enum MemoryPressure: Sendable, Equatable {
    case low
    case warn
    case critical
}
