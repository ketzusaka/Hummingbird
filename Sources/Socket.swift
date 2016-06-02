//
//  Socket.swift
//  Hummingbird
//
//  Created by James Richard on 2/8/16.
//

import C7

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

/// A `Socket` represents a socket descriptor.
public class Socket {

    let socketDescriptor: Int32

    /// `true` if the socket is closed. Otherwise `false`.
    public internal(set) var closed = false

    /** 
     Initialize a `Socket` with a given socket descriptor. The socket descriptor must be open, and further operations on
     the socket descriptor should be through the `Socket` class to properly manage open state.
     
     - parameter    socketDescriptor:   An open socket file descriptor.
    */
    public init(socketDescriptor: Int32) {
        self.socketDescriptor = socketDescriptor
    }

    deinit {
        if !closed {
            let _ = systemClose(socketDescriptor)
        }
    }

    /**
     Sends a sequence of data to the socket. The system send call may be called numberous times to send all of the data
     contained in the sequence.
     
     - parameter        data:       The sequence of data to send.
     - throws:          `ClosableError.alreadyClosed` if the socket is closed.
                        `SocketError.sendFailed` if any invocation of the system send fails.
    */
    #if swift(>=3.0)
    public func send<DataSequence: Sequence where DataSequence.Iterator.Element == Byte>(_ data: DataSequence) throws {
        guard !closed else { throw ClosableError.alreadyClosed }

        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(SO_NOSIGPIPE)
        #endif

        let dataArray = [Byte](data)

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
    public func send<DataSequence: SequenceType where DataSequence.Generator.Element == Byte>(data: DataSequence) throws {
        guard !closed else { throw ClosableError.alreadyClosed }

        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(SO_NOSIGPIPE)
        #endif

        let dataArray = [Byte](data)

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
     - throws:          `ClosableError.alreadyClosed` if the socket is closed.
                        `SocketError.sendFailed` if any invocation of the system send fails.
     */
    public func send(_ string: String) throws {
        try send(string.utf8)
    }

    /**
     Receives a `String` from the socket. The data being sent must be UTF8-encoded data that can be 
     transcoded into a `String`.
     
     - parameter    byteCount:       The amount of space allocated to read data into. This does not ensure that your `String`
                                    will be this size, and does not wait for it to fill. It dictates the maximum amount of data
                                    we can receive within this call.
     - returns:     A `String` representing the data received.
     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.connectionClosedByPeer` if the remote peer signaled the connection is being closed.
                    `SocketError.receiveFailed` when the system recv call fails.
                    `SocketError.stringTranscodingFailed` if the received data could not be transcoded.
    */
    public func receive(upTo byteCount: Int = 1024, timingOut deadline: Double = .never) throws -> String {
        let bytes: [Byte] = try receive(upTo: byteCount, timingOut: deadline)
        guard let transcodedString = String(utf8: bytes) else { throw SocketError.stringTranscodingFailed }
        return transcodedString
    }

    /**
     Receives an array of `Byte` values from the socket.

     - parameter    byteCount:       The amount of space allocated to read data into. This does not ensure that your data
                                    will be this size, and does not wait for it to fill. It dictates the maximum amount of data
                                    we can receive within this call.
     - returns:     The received array of UInt8 values.
     - throws:      `ClosableError.alreadyClosed` if the socket is closed.
                    `SocketError.connectionClosedByPeer` if the remote peer signaled the connection is being closed.
                    `SocketError.receiveFailed` when the system recv call fails.
     */
    public func receive(upTo byteCount: Int = 1024, timingOut deadline: Double = .never) throws -> [Byte] {
        guard !closed else { throw ClosableError.alreadyClosed }
        #if swift(>=3.0)
            let buffer = UnsafeMutablePointer<UInt8>(allocatingCapacity: byteCount)
        #else
            let buffer = UnsafeMutablePointer<UInt8>.alloc(byteCount)
        #endif

        defer {
            #if swift(>=3.0)
                buffer.deallocateCapacity(byteCount)
            #else
                buffer.dealloc(byteCount)
            #endif
        }

        let bytesRead = systemRecv(socketDescriptor, buffer, byteCount, 0)

        if bytesRead == -1 {
            #if swift(>=3.0)
                let message = String(validatingUTF8: strerror(errno))
            #else
                let message = String.fromCString(strerror(errno))
            #endif
            throw SocketError.receiveFailed(code: Int(errno), message: message)
        }

        /*
         A message of zero bytes means that the remote end is about to close the connection. This is
         done so the socket doesn't sit around waiting until the timeout is reached.
        */
        guard bytesRead != 0 else {
            _ = try? close()
            throw SocketError.connectionClosedByPeer
        }

        var readData = [Byte]()
        for i in 0 ..< bytesRead {
            readData.append(buffer[i])
        }

        return readData
    }

    /**
     Closes the socket.
     
     - throws:  `ClosableError.alreadyClosed` if the socket is already closed.
                `SocketError.closeFailed` when the system close command fials
    */
    public func close() throws {
        guard !closed else { throw ClosableError.alreadyClosed }
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
    func getAddrFromHostname(_ hostname: String) throws -> in_addr {
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
            let hostInfo = hostInfoPointer!.pointee
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
    func htons(_ value: CUnsignedShort) -> CUnsignedShort {
        return (value << 8) + (value >> 8)
    }

    func sockaddr_cast(_ p: UnsafeMutablePointer<Void>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }
    
    func sockaddr_in_cast(_ p: UnsafeMutablePointer<sockaddr_in>) -> UnsafeMutablePointer<sockaddr> {
        return UnsafeMutablePointer<sockaddr>(p)
    }

    #if swift(>=3.0)
    func sockadd_list_cast(_ p: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>) -> UnsafeMutablePointer<UnsafeMutablePointer<in_addr>> {
        return UnsafeMutablePointer<UnsafeMutablePointer<in_addr>>(p)
    }
    #else
    func sockadd_list_cast(_ p: UnsafeMutablePointer<UnsafeMutablePointer<Int8>>) -> UnsafeMutablePointer<UnsafeMutablePointer<in_addr>> {
        return UnsafeMutablePointer<UnsafeMutablePointer<in_addr>>(p)
    }
    #endif

    class func createSocketDescriptor() throws -> Int32 {
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

        return sd
    }
    
}

extension Socket: Hashable {
    public var hashValue: Int { return Int(socketDescriptor) }
}

extension Socket: C7.Stream {

    public func receive(upTo byteCount: Int, timingOut deadline: Double) throws -> Data {
        let bytes: [Byte] = try receive(upTo: byteCount, timingOut: deadline)
        return Data(bytes)
    }

    public func send(_ data: Data, timingOut: Double) throws {
        try send(data.bytes)
    }

    public func flush(timingOut: Double) throws {
        // noop; we always send immediately
    }
}

public func ==(lhs: Socket, rhs: Socket) -> Bool {
    return lhs.socketDescriptor == rhs.socketDescriptor
}
