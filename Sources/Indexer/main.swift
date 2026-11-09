import Foundation

if CommandLine.arguments.contains("--version") {
    print("3dSlicerIndexer")
    exit(0)
}

// A separate executable keeps long previews out of the Finder handler's app identity.
// Check conditions on another queue: a single complex mesh can outlive the run budget.
let deadline = Date().addingTimeInterval(20 * 60)
let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .background))
monitor.schedule(deadline: .now() + 5, repeating: 5)
monitor.setEventHandler {
    if let reason = Indexer.whyNotNow() {
        Indexer.write("parou durante preview: \(reason)")
        exit(0)
    }
    if Date() >= deadline {
        Indexer.write("parou durante preview: limite de 20 minutos")
        exit(0)
    }
}
monitor.resume()
Indexer.run(store: Store(), force: false)
