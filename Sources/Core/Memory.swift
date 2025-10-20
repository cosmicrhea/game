#if canImport(Darwin)
  import Darwin
#endif

@inlinable
func reportResidentMemoryBytes() -> UInt64 {
  #if canImport(Darwin)
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(
      MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<natural_t>.stride
    )

    let result: kern_return_t = withUnsafeMutablePointer(to: &info) { ptr in
      ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
        task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
      }
    }

    guard result == KERN_SUCCESS else { return 0 }
    return UInt64(info.phys_footprint)
  #else
    return 0
  #endif
}
