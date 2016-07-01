//
//  ClientSocket.swift
//  Hummingbird
//
//  Created by James Richard on 4/20/16.
//
//

import C7

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

/// A `ClientSocket` is used for opening connections to another socket.
public final class ClientSocket: Socket {

    /// The address to connect to. This can be an IP or hostname.
    public let address: String

    /// The port to connect to.
    public let port: String

    /**
     Creates a new IPv4 TCP socket.

     - throws: `SocketError.socketCreationFailed` if creating the socket failed.
     */
    public init(address: String, port: String) throws {
        self.address = address
        self.port = port
        super.init(socketDescriptor: try Socket.createSocketDescriptor())
    }

}

extension ClientSocket: Connection {

    /**
     Connect to a given host/address and port.

     The socket must be open, and not already connected or binded.

     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.invalidPort` when converting the port to `in_port_t` fails.
                    `SocketError.failedToGetIPFromHostname` when obtaining an IP from a hostname fails.
                    `SocketError.hostInformationIncomplete` if the IP information obtained is incomplete or incompatible.
                    `SocketError.connectFailed` if the system connect fall fails.
     */
    public func open(timingOut: Double = .never) throws {
        guard !closed else { throw ClosableError.alreadyClosed }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        guard let convertedPort = in_port_t(port) else {
            throw SocketError.invalidPort
        }

        if inet_pton(AF_INET, address, &addr.sin_addr) != 1 {
            addr.sin_addr = try getAddrFromHostname(address)
        }

        addr.sin_port = in_port_t(htons(convertedPort))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let len = socklen_t(UInt8(sizeof(sockaddr_in.self)))

        guard systemConnect(socketDescriptor, sockaddr_cast(&addr), len) >= 0 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.connectFailed(code: Int(errno), message: message)
        }
    }

}
