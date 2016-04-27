//
//  ServerSocket.swift
//  Hummingbird
//
//  Created by James Richard on 4/20/16.
//
//

import C7
import Strand

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

/// A `ServerSocket` is used for accepting connections from another socket.
public final class ServerSocket: Socket {

    /// The address to bind to. If `nil`, bind to any address.
    public let address: String?

    /// The port to bind to. If `nil`, bind to any port.
    public let port: String?

    /**
     Creates a new IPv4 TCP socket.

     - throws: `SocketError.socketCreationFailed` if creating the socket failed.
     */
    public init(address: String? = nil, port: String? = nil) throws {
        self.address = address
        self.port = port
        super.init(socketDescriptor: try Socket.createSocketDescriptor())
    }

    /**
     Binds the socket to a given address and port.

     The socket must be open, and must not already be binded.

     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.socketConfigurationFailed` when setting SO_REUSEADDR on the socket fails.
                    `SocketError.invalidPort` when converting the port to `in_port_t` fails.
                    `SocketError.bindingFailed` if the system bind command fails.
     */
    public func bind() throws {
        guard !closed else { throw ClosableError.alreadyClosed }
        var optval: Int = 1;

        guard setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(sizeof(Int))) != -1 else {
            systemClose(socketDescriptor)
            closed = true
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.socketConfigurationFailed(code: Int(errno), message: message)
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        if let port = port {
            guard let convertedPort = in_port_t(port) else {
                throw SocketError.invalidPort
            }

            addr.sin_port = in_port_t(htons(convertedPort))
        }

        if let address = address {
            try address.withCString {
                var s_addr = in_addr()

                guard inet_pton(AF_INET, $0, &s_addr) == 1 else {
                    #if swift(>=3.0)
                        let message = String(validatingUTF8: strerror(errno))
                    #else
                        let message = String.fromCString(strerror(errno))
                    #endif
                    throw SocketError.bindingFailed(code: Int(errno), message: message)
                }

                addr.sin_addr = s_addr
            }
        }

        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let len = socklen_t(UInt8(sizeof(sockaddr_in)))
        guard systemBind(socketDescriptor, sockaddr_cast(&addr), len) != -1 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.bindingFailed(code: Int(errno), message: message)
        }
    }

    /**
     Listen for connections.

     - parameter    backlog:    The maximum length for the queue of pending connections.
     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.listenFailed` if the system listen fails.
     */
    public func listen(pendingConnectionBacklog backlog: Int = 100) throws {
        guard !closed else { throw ClosableError.alreadyClosed }

        if systemListen(socketDescriptor, Int32(backlog)) != 0 {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.listenFailed(code: Int(errno), message: message)
        }
    }

    /**
     Begin accepting connections. When a connection is accepted, the `connectionHandler` is passed a new `Socket`
     that can communicate with the peer. The `connectionHandler` is executed on a new thread.

     - parameter    maximumConsecutiveFailures:     The maximum number of failures the system accept can have consecutively.
                                                    Passing a negative number means an unlimited number of consecutive errors.
                                                    Defaults to SOMAXCONN.
     - parameter    connectionHandler:              The closure executed when a connection is established.
     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.acceptConsecutivelyFailing` if a the system accept fails a consecutive number of times that
                    exceeds a positive `maximumConsecutiveFailures`.
     */
    public func accept(maximumConsecutiveFailures: Int = Int(SOMAXCONN), connectionHandler: (Socket) -> Void) throws {
        guard !closed else { throw ClosableError.alreadyClosed }

        var consecutiveFailedAccepts = 0
        ACCEPT_LOOP: while true {
            do {
                let socket = try accept(timingOut: .never) as! Socket
                consecutiveFailedAccepts = 0

                _ = try Strand {
                    connectionHandler(socket)
                }
            } catch let e as SocketError where e.isAcceptFailed {
                consecutiveFailedAccepts += 1
                guard maximumConsecutiveFailures >= 0 && consecutiveFailedAccepts < maximumConsecutiveFailures else {
                    throw e
                }
            }
        }
    }
    
}

extension ServerSocket: Host {

    public func accept(timingOut deadline: Double) throws -> Stream {
        guard !closed else { throw ClosableError.alreadyClosed }

        let requestDescriptor = systemAccept(socketDescriptor, nil, nil)

        guard requestDescriptor != -1 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.acceptFailed(code: Int(errno), message: message)
        }
        
        return Socket(socketDescriptor: requestDescriptor)
    }

}

extension SocketError {

    private var isAcceptFailed: Bool {
        switch self {
        case .acceptFailed(code: _, message: _): return true
        default: return false
        }
    }

}
