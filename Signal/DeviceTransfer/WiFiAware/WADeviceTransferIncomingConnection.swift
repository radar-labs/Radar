//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Network
import SignalServiceKit
import WiFiAware

@available(iOS 26.0, *)
class WADeviceTransferIncomingConnection: DeviceTransfer.IncomingConnection {
    private let logger = PrefixedLogger(prefix: "[DeviceTransfer][WiFiAware][Incoming]")

    private enum Constants {
        /// How long to wait for a cancelled listener to actually unwind.
        static let listenerStopTimeout: TimeInterval = 5
    }

    private var discoveredPeerTask: Task<Void, Never>?

    private enum ListenerPhase {
        case waiting // No connection yet, peer changes can restart the listener
        case connected // Connected, ignore any peer changes
        case restarting // Peer change encountered, don't accept connections while restarting
    }

    private struct ListenerState {
        var task: Task<Void, any Error>?
        var isStopped = false
    }

    private let listenerState = AtomicValue<ListenerState>(ListenerState(), lock: .init())

    let discoveredPeerStream: AsyncThrowingStream<[any DeviceTransfer.Peer], any Error>

    /// Internal peer stream broacaster monitored by this class for connection management
    private let peers: AsyncStreamBroadcast<[any DeviceTransfer.Peer]>

    let identity: SecIdentity
    let secIdentity: sec_identity_t

    init() throws {
        self.identity = try SelfSignedIdentity.create(name: "IncomingDeviceTransfer", validForDays: 1)
        guard let secIdentity = sec_identity_create(identity) else {
            throw OWSAssertionError("Unexpected identity format")
        }
        self.secIdentity = secIdentity
        let (internalPeerStream, peerTask) = WiFiAware.createPeerDiscoveryObserver(logger: logger)
        self.discoveredPeerTask = peerTask
        let peers = AsyncStreamBroadcast<[any DeviceTransfer.Peer]>(initialValue: [])
        self.peers = peers
        self.discoveredPeerStream = peers.subscribe()

        Task {
            do {
                for try await peerList in internalPeerStream {
                    // Publish peer data to any internal subscribers
                    peers.update(peerList)
                }
            } catch is CancellationError {
                // Nothing
            } catch {
                owsFailDebug("Peer discovery stream errored! \(error)")
            }
        }
    }

    deinit {
        listenerState.update { $0.task.take()?.cancel() }
        discoveredPeerTask.take()?.cancel()
    }

    func start(mode: DeviceTransfer.Mode) throws -> URL {
        var components = URLComponents()
        components.scheme = UrlOpener.Constants.sgnlPrefix
        components.host = DeviceTransfer.UrlConstants.transferHost
        let queryItems = [
            DeviceTransfer.UrlConstants.versionKey: String(DeviceTransfer.UrlConstants.currentTransferVersion),
            DeviceTransfer.UrlConstants.transferModeKey: mode.rawValue,
            DeviceTransfer.UrlConstants.certificateHashKey:
                try identity.computeCertificateHash().base64EncodedString().encodeURIComponent ?? "",
        ]
        components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }

    func waitForConnection(peer: (any DeviceTransfer.Peer)?) async throws -> any DeviceTransfer.Session {
        logger.info("Wait for connection")
        let allowedConnections: WAPublisherListener.Devices
        if let waPeer = peer as? WADeviceTransferPeer {
            logger.info("Accepting connections from \(waPeer)")
            allowedConnections = .selected([waPeer.pairedDevice])
        } else {
            logger.info("Accepting connections from all paired devices")
            allowedConnections = .allPairedDevices
        }

        // Subscribe and wait for the first list of peers
        for try await peerList in peers.subscribe() {
            // Open the listener even when nothing is paired yet. The old device can
            // discover and connect to us through the service published by
            // `DevicePairingView` before any pairing record exists on this side, and
            // if no listener is up when it does, it connects, starts sending, and
            // stalls with nothing in either log to say why. In a perfect world, this behavior
            // should be avoided by steering the user away from `DevicePairingView` through
            // hints in the UI, but the user should always have the option to enter the
            // `DevicePairingView` to pair new devices, even when there are known paired devices.
            if peerList.isEmpty {
                logger.info("No paired devices yet, listening for the first pairing")
            }

            let phase = AtomicValue<ListenerPhase>(.waiting, lock: .init())
            // Set up two tasks - one to open a connection, and one to listen for any new peers.
            let session = try await withThrowingTaskGroup(of: (any DeviceTransfer.Session)?.self) { group in
                group.addTask { [weak self, logger] in
                    // This feels a little hacky, but it seems that newly peered devices take a
                    // little bit to show up at the NetworkListener layer.  If the listener is
                    // opened too quickly, the new peer won't be in the list of allowable connections
                    // and things will stall. Adding a small forced delay helps to let the pairing
                    // info settle before making connections based on it.
                    try await Task.sleep(nanoseconds: 1.clampedNanoseconds)

                    try Task.checkCancellation()
                    do {
                        logger.info("Begin listening for connection")
                        return try await self?.listenForConnection(
                            allowedDevices: allowedConnections,
                            phase: phase,
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        guard peerList.isEmpty else { throw error }
                        logger.info("Listener failed (\(error)); waiting for peer")
                        return nil
                    }
                }
                group.addTask { @MainActor [weak self] in
                    guard let self else { return nil }
                    // If the list of peers changes, return 'nil' to signify that we need
                    // to cancel the current listener and start over with a new iteration of the
                    // outer for-await loop
                    for try await next in self.peers.subscribe() {
                        let nextSet = Set(next.map(\.id))
                        let peerListSet = Set(peerList.map(\.id))
                        if !nextSet.symmetricDifference(peerListSet).isEmpty {
                            let shouldRestart = phase.update {
                                guard $0 == .waiting else { return false }
                                $0 = .restarting
                                return true
                            }
                            if shouldRestart {
                                self.logger.info("New peer discovered, restarting listener")
                                return nil
                            }
                            self.logger.info("Ignored peer list changed after connection; keeping current connection.")
                        }
                    }
                    return nil
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }

            if let session {
                return session
            }
        }

        try Task.checkCancellation() // If we reached here w/o a result, check for cancellation
        throw OWSAssertionError("Peer stream ended without producing a connection")
    }

    private func listenForConnection(
        allowedDevices: WAPublisherListener.Devices,
        phase: AtomicValue<ListenerPhase>,
    ) async throws -> DeviceTransfer.Session {

        // Ensure that any existing task is cleaned up before starting a new one
        await tearDownListener(task: listenerState.update { $0.task.take() })

        let continuation = CancellableContinuation<DeviceTransfer.Session>()
        let newTask = Task { [logger, secIdentity] in
            logger.info("Open connection")
            try await NetworkListener(
                for: .wifiAware(
                    .connecting(
                        to: .deviceTransferService,
                        from: allowedDevices,
                    ),
                ),
                using: .parameters {
                    Coder(
                        receiving: WiFiAware.NetworkEvent.self,
                        sending: WiFiAware.NetworkEvent.self,
                        using: NetworkJSONCoder(),
                    ) {
                        TLS() {
                            TCP().keepalive(
                                idleTimeInSeconds: 10,
                                count: 30,
                                intervalInSeconds: 5,
                            )
                        }
                        .localIdentity(secIdentity)
                    }
                },
            ).onStateUpdate { _, state in
                switch state {
                case .setup:
                    logger.info("Connection: setup")
                case .ready:
                    logger.info("Connection: ready")
                case .failed(let error):
                    logger.info("Connection: failed: \(error)")
                    continuation.resume(with: .failure(error))
                case .cancelled:
                    logger.info("Connection: cancelled")
                    continuation.resume(with: .failure(CancellationError()))
                case .waiting(let error):
                    logger.info("Connection: waiting: \(error)")
                @unknown default:
                    logger.warn("Connection: unhandled state: \(state)")
                }
            }.onServiceRegistrationUpdate { _, change in
                switch change {
                case .add:
                    logger.info("Connection: add service")
                case .remove:
                    logger.info("Connection: remove service")
                @unknown default:
                    logger.warn("Connection: unhandled service registration: \(change)")
                }
            }.run { connection in
                let accepted = phase.update {
                    guard $0 == .waiting else { return false }
                    $0 = .connected
                    return true
                }
                guard accepted else {
                    // Only allow one connection to this endpoint at a time, and reject
                    // any connections during a restart due to peer change
                    logger.info("Rejected additional connection")
                    return
                }
                logger.info("Connection from endpoint")
                let session = WADeviceTransferSession(connection: connection)
                continuation.resume(with: .success(session))
                try await session.waitForCompletion()
            }
        }

        let setNewTask = listenerState.update { state in
            guard !state.isStopped else { return false }
            state.task = newTask
            return true
        }
        guard setNewTask else {
            newTask.cancel()
            throw CancellationError()
        }

        do {
            let session = try await continuation.wait()
            logger.info("Returning new session")
            return session
        } catch {
            await tearDownListener(task: listenerState.update { $0.task.take() })
            phase.update { if $0 == .connected { $0 = .waiting } }
            throw error
        }
    }

    func stop(error: Error?) async {
        let task = listenerState.update {
            // Mark as stopped, so any attempts to start a new listener are immediately cancelled
            $0.isStopped = true
            return $0.task.take()
        }
        await tearDownListener(task: task)
    }

    private func tearDownListener(task: Task<Void, any Error>?) async {
        guard let task else {
            logger.info("Stop: no listener to tear down")
            return
        }
        logger.info("Stop: cancelling listener")
        task.cancel()
        // Since this may execute in an already cancelled task, run this in an unstrucutured
        // task that doesn't inherit cancelled state.  Without this, the timeout may not fire
        // and the cancellation could block longer than intended.
        await Task {
            do {
                try await withCooperativeTimeout(seconds: Constants.listenerStopTimeout) {
                    _ = await task.result
                }
                logger.info("Stop: listener torn down")
            } catch {
                logger.warn("Stop: listener still running after \(Constants.listenerStopTimeout)s: \(error)")
            }
        }.value
    }
}

private class AsyncStreamBroadcast<T> {

    struct State {
        var latest: T
        var sinks: [UUID: AsyncThrowingStream<T, any Error>.Continuation] = [:]
    }

    let state: AtomicValue<State>

    init(initialValue: T) {
        self.state = AtomicValue(State(latest: initialValue), lock: .init())
    }

    func update(_ value: T) {
        let sinks = state.update {
            $0.latest = value
            return $0.sinks.values
        }
        sinks.forEach { $0.yield(value) }
    }

    func subscribe() -> AsyncThrowingStream<T, any Error> {
        let id = UUID()
        let (stream, sink) = AsyncThrowingStream<T, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        sink.onTermination = { [weak self] _ in self?.unsubscribe(id: id) }
        let latest = state.update {
            $0.sinks[id] = sink
            return $0.latest
        }
        sink.yield(latest)
        return stream
    }

    private func unsubscribe(id: UUID) {
        state.update {
            $0.sinks[id] = nil
        }
    }
}
