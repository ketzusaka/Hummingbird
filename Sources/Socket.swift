//
//  Socket.swift
//  Hummingbird
//
//  Created by James Richard on 2/8/16.
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

#if !swift(>=3.0)
    public typealias ErrorProtocol = ErrorType
#endif

public enum SocketError: ErrorProtocol {
    case acceptConsecutivelyFailing(code: Int, message: String?)
    case bindingFailed(code: Int, message: String?)
    case bufferReadFailed
    case closeFailed(code: Int, message: String?)
    case listenFailed(code: Int, message: String?)
    case receiveFailed(code: Int, message: String?)
    case connectFailed(code: Int, message: String?)
    case hostInformationIncomplete(message: String)
    case invalidData
    case invalidPort
    case sendFailed(code: Int, message: String?, sent: Int)
    case obtainingAddressInformationFailed(code: Int, message: String?)
    case socketCreationFailed(code: Int, message: String?)
    case socketConfigurationFailed(code: Int, message: String?)
    case socketClosed
    case stringTranscodingFailed
    case failedToGetIPFromHostname(code: Int, message: String?)
}

/// A `Socket` represents a socket descriptor.
public final class Socket {
    let socketDescriptor: Int32
    private var closed = false

    /** 
     Initialize a `Socket` with a given socket descriptor. The socket descriptor must be open, and further operations on
     the socket descriptor should be through the `Socket` class to properly manage open state.
     
     - parameter    socketDescriptor:   An open socket file descriptor.
    */
    public init(socketDescriptor: Int32) {
        self.socketDescriptor = socketDescriptor
    }

    /**
     Creates a new IPv4 TCP socket.
     
     - throws: `SocketError.SocketCreationFailed` if creating the socket failed.
    */
    public class func makeStreamSocket() throws -> Socket {
        #if os(Linux)
            let sd = socket(AF_INET, sockStream, 0)
        #else
            let sd = socket(AF_INET, sockStream, IPPROTO_TCP)
        #endif

        guard sd >= 0 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.socketCreationFailed(code: Int(errno), message: message)
        }

        return Socket(socketDescriptor: sd)
    }

    deinit {
        if !closed {
            systemClose(socketDescriptor)
        }
    }

    /**
     Binds the socket to a given address and port. 

     The socket must be open, and must not already be binded.
     
     - parameter    address:    The address to bind to. If no address is given, use any address.
     - parameter    port:       The port to bind it. If no port is given, bind to a random port.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.SocketConfigurationFailed` when setting SO_REUSEADDR on the socket fails.
                    `SocketError.InvalidPort` when converting the port to `in_port_t` fails. 
                    `SocketError.BindingFailed` if the system bind command fails.
    */
    public func bind(toAddress address: String? = nil, onPort port: String? = nil) throws {
        guard !closed else { throw SocketError.socketClosed }
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
     Connect to a given host/address and port.
     
     The socket must be open, and not already connected or binded.
     
     - parameter    target:     The host or address to connect to. This can be an IPv4 address, or a hostname that
                                can be resolved to an IPv4 address.
     - parameter    port:       The port to connect to.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.InvalidPort` when converting the port to `in_port_t` fails.
                    `SocketError.FailedToGetIPFromHostname` when obtaining an IP from a hostname fails.
                    `SocketError.HostInformationIncomplete` if the IP information obtained is incomplete or incompatible.
                    `SocketError.ConnectFailed` if the system connect fall fails.
    */
    public func connect(toTarget target: String, onPort port: String) throws {
        guard !closed else { throw SocketError.socketClosed }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)

        guard let convertedPort = in_port_t(port) else {
            throw SocketError.invalidPort
        }

        if inet_pton(AF_INET, target, &addr.sin_addr) != 1 {
            addr.sin_addr = try getAddrFromHostname(target)
        }

        addr.sin_port = in_port_t(htons(convertedPort))
        addr.sin_zero = (0, 0, 0, 0, 0, 0, 0, 0)

        let len = socklen_t(UInt8(sizeof(sockaddr_in)))

        guard systemConnect(socketDescriptor, sockaddr_cast(&addr), len) >= 0 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.connectFailed(code: Int(errno), message: message)
        }
    }

    /**
     Listen for connections.

     - parameter    backlog:    The maximum length for the queue of pending connections.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.ListenFailed` if the system listen fails.
    */
    public func listen(pendingConnectionBacklog backlog: Int = 100) throws {
        guard !closed else { throw SocketError.socketClosed }

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
     Begin accepting connections. When a connection is accepted, a new thread is created by the system `accept` command.
     
     - parameter    maximumConsecutiveFailures:     The maximum number of failures the system accept can have consecutively.
                                                    Passing a negative number means an unlimited number of consecutive errors.
                                                    Defaults to SOMAXCONN.
     - parameter    connectionHandler:              The closure executed when a connection is established.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.AcceptConsecutivelyFailing` if a the system accept fails a consecutive number of times that
                    exceeds a positive `maximumConsecutiveFailures`.
    */
    public func accept(maximumConsecutiveFailures: Int = Int(SOMAXCONN), connectionHandler: (Socket) -> Void) throws {
        guard !closed else { throw SocketError.socketClosed }

        var consecutiveFailedAccepts = 0
        ACCEPT_LOOP: while true {
            var connectedAddrInfo = sockaddr_in()
            var connectedAddrInfoLength = socklen_t(sizeof(sockaddr_in))

            let requestDescriptor = systemAccept(socketDescriptor, sockaddr_cast(&connectedAddrInfo), &connectedAddrInfoLength)

            if requestDescriptor == -1 {
                consecutiveFailedAccepts += 1
                guard maximumConsecutiveFailures >= 0 && consecutiveFailedAccepts < maximumConsecutiveFailures else {
                    #if swift(>=3.0)
                        let message = String(validatingUTF8: strerror(errno))
                    #else
                        let message = String.fromCString(strerror(errno))
                    #endif
                    throw SocketError.acceptConsecutivelyFailing(code: Int(errno), message: message)
                }
                continue
            }

            consecutiveFailedAccepts = 0

            _ = try Strand {
                connectionHandler(Socket(socketDescriptor: requestDescriptor))
            }
        }
    }

    /**
     Sends a sequence of data to the socket. The system send call may be called numberous times to send all of the data
     contained in the sequence.
     
     - parameter        data:       The sequence of data to send.
     - throws:          `SocketError.SocketClosed` if the socket is closed.
                        `SocketError.SendFailed` if any invocation of the system send fails.
    */
    #if swift(>=3.0)
    public func send<DataSequence: Sequence where DataSequence.Iterator.Element == UInt8>(_ data: DataSequence) throws {
        guard !closed else { throw SocketError.socketClosed }

        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(0)
        #endif

        let dataArray = [UInt8](data)

        try dataArray.withUnsafeBufferPointer { buffer in
            var sent = 0
            guard let base = buffer.baseAddress else { throw SocketError.bufferReadFailed }
            while sent < dataArray.count {
                let s = systemSend(socketDescriptor, base + sent, dataArray.count - sent, flags)

                if s == -1 {
                    throw SocketError.sendFailed(code: Int(errno), message: String(validatingUTF8: strerror(errno)), sent: sent)
                }

                sent += s
            }
        }
    }
    #else
    public func send<DataSequence: SequenceType where DataSequence.Generator.Element == UInt8>(data: DataSequence) throws {
        guard !closed else { throw SocketError.socketClosed }

        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(0)
        #endif

        let dataArray = [UInt8](data)

        try dataArray.withUnsafeBufferPointer { buffer in
            var sent = 0
            while sent < dataArray.count {
                let s = systemSend(socketDescriptor, buffer.baseAddress + sent, dataArray.count - sent, flags)

                if s == -1 {
                    throw SocketError.sendFailed(code: Int(errno), message: String.fromCString(strerror(errno)), sent: sent)
                }

                sent += s
            }
        }
    }
    #endif

    /**
     Sends a `String` to the socket. The string is sent in its UTF8 representation. The system send call may 
     be called numberous times to send all of the data contained in the sequence.

     - parameter        string:     The string to send.
     - throws:          `SocketError.SocketClosed` if the socket is closed.
                        `SocketError.SendFailed` if any invocation of the system send fails.
     */
    public func send(_ string: String) throws {
        try send(string.utf8)
    }

    /**
     Receives a `String` from the socket. The data being sent must be UTF8-encoded data that can be 
     transcoded into a `String`.
     
     - parameter    bufferSize:     The amount of space allocated to read data into. This does not ensure that your `String`
                                    will be this size, and does not wait for it to fill. It dictates the maximum amount of data
                                    we can receive within this call.
     - returns:     A `String` representing the data received.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.ReceiveFailed` when the system recv call fails.
                    `SocketError.StringTranscodingFailed` if the received data could not be transcoded.
    */
    public func receive(maximumBytes bufferSize: Int = 1024) throws -> String {
        guard let transcodedString = String(utf8: try receive(maximumBytes: bufferSize)) else { throw SocketError.stringTranscodingFailed }
        return transcodedString
    }

    /**
     Receives an array of `UInt8` values from the socket.

     - parameter    bufferSize:     The amount of space allocated to read data into. This does not ensure that your data
                                    will be this size, and does not wait for it to fill. It dictates the maximum amount of data
                                    we can receive within this call.
     - returns:     The received array of UInt8 values.
     - throws:      `SocketError.SocketClosed` if the socket is closed.
                    `SocketError.ReceiveFailed` when the system recv call fails.
     */
    public func receive(maximumBytes bufferSize: Int = 1024) throws -> [UInt8] {
        guard !closed else { throw SocketError.socketClosed }
        #if swift(>=3.0)
            let buffer = UnsafeMutablePointer<UInt8>(allocatingCapacity: bufferSize)
        #else
            let buffer = UnsafeMutablePointer<UInt8>.alloc(bufferSize)
        #endif

        defer {
            #if swift(>=3.0)
                buffer.deallocateCapacity(bufferSize)
            #else
                buffer.dealloc(bufferSize)
            #endif
        }

        let bytesRead = systemRecv(socketDescriptor, buffer, bufferSize, 0)

        if bytesRead == -1 {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.receiveFailed(code: Int(errno), message: message)
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

    /**
     Closes the socket.
     
     - throws:  `SocketError.SocketClosed` if the socket is already closed.
                `SocketError.CloseFailed` when the system close command fials
    */
    public func close() throws {
        guard !closed else { throw SocketError.socketClosed }
        guard systemClose(socketDescriptor) != -1 else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.closeFailed(code: Int(errno), message: message)
        }
        closed = true
    }

    // MARK: - Host resolution
    // Parts of this adapted from https://github.com/czechboy0/Redbird/blob/466056bba8f160b5a9e270be580bb09cf12e1306/Sources/Redbird/ClientSocket.swift#L126-L142
    private func getAddrFromHostname(_ hostname: String) throws -> in_addr {
        let hostInfoPointer = systemGetHostByName(hostname)

        guard hostInfoPointer != nil else {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.failedToGetIPFromHostname(code: Int(errno), message: message)
        }

        #if swift(>=3.0)
            let hostInfo = hostInfoPointer.pointee
        #else
            let hostInfo = hostInfoPointer.memory
        #endif

        guard hostInfo.h_addrtype == AF_INET else {
            throw SocketError.hostInformationIncomplete(message: "No IPv4 address")
        }

        #if swift(>=3.0)
            guard let addrList = hostInfo.h_addr_list else {
                throw SocketError.hostInformationIncomplete(message: "List is empty")
            }
        #else
            guard hostInfo.h_addr_list != nil else {
                throw SocketError.hostInformationIncomplete(message: "List is empty")
            }

            let addrList = hostInfo.h_addr_list
        #endif


        #if swift(>=3.0)
            let addrStruct = sockadd_list_cast(addrList)[0].pointee
        #else
            let addrStruct = sockadd_list_cast(addrList)[0].memory
        #endif

        return addrStruct
    }


    // MARK: - Utility casts
    private func htons(_ value: CUnsignedShort) -> CUnsignedShort {
        return (value << 8) + (value >> 8)
    }

    private func sockaddr_cast(_ p: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    
    private func sockaddr_in_cast(_ p: UnsafeMutablePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    #if swift(>=3.0)
    private func sockadd_list_cast(_ p: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>) -> UnsafeMutablePointer<UnsafeMutablePointer<in_addr>> {
        return UnsafeMutablePointer<UnsafeMutablePointer<in_addr>>(p)
    }
    #else
    private func sockadd_list_cast(_ p: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>) -> UnsafeMutablePointer<UnsafeMutablePointer<in_addr>> {
        return UnsafeMutablePointer<UnsafeMutablePointer<in_addr>>(p)
    }
    #endif
}

extension Socket: Hashable {
    public var hashValue: Int { return Int(socketDescriptor) }
}

public func ==(lhs: Socket, rhs: Socket) -> Bool {
    return lhs.socketDescriptor == rhs.socketDescriptor
}
