//
//  Socket.swift
//  Hummingbird
//
//  Created by James Richard on 2/8/16.
//
//

import Strand

#if os(Linux)
    import Glibc
    let sockStream = Int32(SOCK_STREAM.rawValue)
    let systemAccept = Glibc.accept
    let systemClose = Glibc.close
    let systemListen = Glibc.listen
    let systemRecv = Glibc.recv
    let systemSend = Glibc.send
    let systemBind = Glibc.bind
    let systemConnect = Glibc.connect
    let systemGetHostByName = Glibc.gethostbyname
#else
    import Darwin.C
    let sockStream = SOCK_STREAM
    let systemAccept = Darwin.accept
    let systemClose = Darwin.close
    let systemListen = Darwin.listen
    let systemRecv = Darwin.recv
    let systemSend = Darwin.send
    let systemBind = Darwin.bind
    let systemConnect = Darwin.connect
    let systemGetHostByName = Darwin.gethostbyname
#endif

public enum SocketError: ErrorType {
    case AcceptConsecutivelyFailing(Int, String?)
    case BindingFailed(Int, String?)
    case ListenFailed(Int, String?)
    case RecvFailed(Int, String?)
    case ConnectFailed(Int, String?)
    case HostInformationIncomplete(String)
    case InvalidData
    case InvalidPort
    case SendFailed(Int, String?)
    case ObtainingAddressInformationFailed(Int, String?)
    case SocketCreationFailed(Int, String?)
    case SocketConfigurationFailed(Int, String?)
    case SocketClosed
    case FailedToGetIPFromHostname(Int, String?)
}

public class Socket {
    let socketDescriptor: Int32
    private var closed = false

    public init(socketDescriptor: Int32) {
        self.socketDescriptor = socketDescriptor
    }

    public class func streamSocket() throws -> Socket {
        #if os(Linux)
            let sd = socket(AF_INET, sockStream, 0)
        #else
            let sd = socket(AF_INET, sockStream, IPPROTO_TCP)
        #endif

        guard sd >= 0 else {
            throw SocketError.SocketCreationFailed(Int(errno), String.fromCString(strerror(errno)))
        }

        return Socket(socketDescriptor: sd)
    }

    deinit {
        if !closed {
            systemClose(socketDescriptor)
        }
    }

    public func bind(address: String?, port: String?) throws {
        guard !closed else { throw SocketError.SocketClosed }
        var optval: Int = 1;

        guard setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &optval, socklen_t(sizeof(Int))) != -1 else {
            systemClose(socketDescriptor)
            closed = true
            throw SocketError.SocketConfigurationFailed(Int(errno), String.fromCString(strerror(errno)))
        }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        if let port = port {
            guard let convertedPort = in_port_t(port) else {
                throw SocketError.InvalidPort
            }

            addr.sin_port = in_port_t(htons(convertedPort))
        }

        if let address = address {
            addr.sin_addr = in_addr(s_addr: address.withCString { inet_addr($0) })
        }

        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let len = socklen_t(UInt8(sizeof(sockaddr_in)))
        guard systemBind(socketDescriptor, sockaddr_cast(&addr), len) != -1 else {
            throw SocketError.BindingFailed(Int(errno), String.fromCString(strerror(errno)))
        }
    }

    public func connect(address: String, port: String) throws {
        guard !closed else { throw SocketError.SocketClosed }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        guard let convertedPort = in_port_t(port) else {
            throw SocketError.InvalidPort
        }

        if inet_pton(AF_INET, address, &addr.sin_addr) != 1 {
            addr.sin_addr = try getAddrFromHostname(address)
        }

        addr.sin_port = in_port_t(htons(convertedPort))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let len = socklen_t(UInt8(sizeof(sockaddr_in)))

        guard systemConnect(socketDescriptor, sockaddr_cast(&addr), len) >= 0 else {
            throw SocketError.ConnectFailed(Int(errno), String.fromCString(strerror(errno)))
        }
    }

    public func listen() throws {
        guard !closed else { throw SocketError.SocketClosed }

        if systemListen(socketDescriptor, 100) != 0 {
            throw SocketError.ListenFailed(Int(errno), String.fromCString(strerror(errno)))
        }
    }

    public func accept(connectionHandler: (Socket) -> Void) throws {
        guard !closed else { throw SocketError.SocketClosed }

        var consecutiveFailedAccepts = 0
        ACCEPT_LOOP: while true {
            var connectedAddrInfo = sockaddr_in()
            var connectedAddrInfoLength = socklen_t(sizeof(sockaddr_in))

            let requestDescriptor = systemAccept(socketDescriptor, sockaddr_cast(&connectedAddrInfo), &connectedAddrInfoLength)

            if requestDescriptor == -1 {
                consecutiveFailedAccepts += 1
                guard consecutiveFailedAccepts < 10 else {
                    throw SocketError.AcceptConsecutivelyFailing(Int(errno), String.fromCString(strerror(errno)))
                }
                continue
            }

            consecutiveFailedAccepts = 0

            _ = try Strand {
                connectionHandler(Socket(socketDescriptor: requestDescriptor))
            }
        }
    }

    public func send(data: [UInt8]) throws {
        guard !closed else { throw SocketError.SocketClosed }

        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(0)
        #endif

        let status = systemSend(socketDescriptor, data, data.count, flags)

        if status == -1 {
            throw SocketError.SendFailed(Int(errno), String.fromCString(strerror(errno)))
        }
    }

    public func send(string: String) throws {
        guard !closed else { throw SocketError.SocketClosed }
        try send(string.utf8.map({ $0 as UInt8 }))
    }

    public func recv(bufferSize: Int = 1024) throws -> String? {
        guard !closed else { throw SocketError.SocketClosed }
        return String(utf8: try recv(bufferSize))
    }

    public func recv(bufferSize: Int = 1024) throws -> [UInt8] {
        guard !closed else { throw SocketError.SocketClosed }
        let buffer = UnsafeMutablePointer<UInt8>.alloc(bufferSize)

        defer { buffer.dealloc(bufferSize) }

        let bytesRead = systemRecv(socketDescriptor, buffer, bufferSize, 0)

        if bytesRead == -1 {
            throw SocketError.RecvFailed(Int(errno), String.fromCString(strerror(errno)))
        }

        guard bytesRead != 0 else {
            return []
        }

        var readData = [UInt8]()
        for i in 0 ..< bytesRead {
            readData.append(buffer[i])
        }

        return readData
    }

    public func close() {
        systemClose(socketDescriptor)
        closed = true
    }

    // MARK: - Host resolution
    private func getAddrFromHostname(hostname: String) throws -> in_addr {
        let hostInfoPointer = systemGetHostByName(hostname)

        guard hostInfoPointer != nil else {
            throw SocketError.FailedToGetIPFromHostname(Int(errno), String.fromCString(strerror(errno)))
        }

        let hostInfo = hostInfoPointer.memory

        guard hostInfo.h_addrtype == AF_INET else {
            throw SocketError.HostInformationIncomplete("No IPv4 address")
        }

        guard hostInfo.h_addr_list != nil else {
            throw SocketError.HostInformationIncomplete("List is empty")
        }

        let addrStruct = sockadd_list_cast(hostInfo.h_addr_list)[0].memory
        return addrStruct
    }


    // MARK: - Utility casts
    private func htons(value: CUnsignedShort) -> CUnsignedShort {
        return (value << 8) + (value >> 8)
    }

    private func sockaddr_cast(p: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    
    private func sockaddr_in_cast(p: UnsafeMutablePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }

    private func sockadd_list_cast(p: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>) -> UnsafeMutablePointer<UnsafeMutablePointer<in_addr>> {
        return UnsafeMutablePointer<UnsafeMutablePointer<in_addr>>(p)
    }
}
