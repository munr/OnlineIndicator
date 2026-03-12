import Network

class NetworkMonitor {

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitorQueue")

    var pathChangedHandler: (() -> Void)?

    private(set) var isConnected: Bool = false

    func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.pathChangedHandler?()
            }
        }

        monitor.start(queue: queue)
        
        isConnected = monitor.currentPath.status == .satisfied
    }
}
