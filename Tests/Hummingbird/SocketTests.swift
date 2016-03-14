@testable import Hummingbird
import Strand
import XCTest

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

#if os(Linux)
    extension SocketTests: XCTestCaseProvider {
        var allTests : [(String, () throws -> Void)] {
            return [
                ("testSendingRawDataToSocket_sendsDataCorrectly", testSendingRawDataToSocket_sendsDataCorrectly),
                ("testSendingStringDataToSocket_sendsDataCorrectly", testSendingStringDataToSocket_sendsDataCorrectly),
                ("testReceivingRawDataToSocket_readsCorrectly", testReceivingRawDataToSocket_readsCorrectly),
                ("testReceivingStringDataToSocket_readsCorrectly", testReceivingStringDataToSocket_readsCorrectly),
                ("testBind_withInvalidAddress_throwsCorrectException", testBind_withInvalidAddress_throwsCorrectException),
                ("testBind_withInvalidPort_throwsCorrectException", testBind_withInvalidPort_throwsCorrectException),
                ("testBind_bindsCorrectly", testBind_bindsCorrectly)
            ]
        }
    }
#endif

class SocketTests: XCTestCase {
	func testSendingRawDataToSocket_sendsDataCorrectly() {
        var sds: [Int32] = [0,0]

        if socketpair(AF_UNIX, Hummingbird.sockStream, 0, &sds) == -1 {
            XCTFail("Unable to create socket pair")
            return
        }

        let sendableData = [2, 5, 10] as [UInt8]

        let s = Socket(socketDescriptor: sds[0])
        _ = try! Strand {
            do {
                try s.send(sendableData)
            } catch let error {
                XCTFail("Unable to send data to socket due to error: \(error)")
            }
        }

        let data = try! readDataFromSocket(sds[1])

        XCTAssertEqual(data, sendableData)
    }

    func testSendingStringDataToSocket_sendsDataCorrectly() {
        var sds: [Int32] = [0,0]

        if socketpair(AF_UNIX, Hummingbird.sockStream, 0, &sds) == -1 {
            XCTFail("Unable to create socket pair")
            return
        }

        let sendableData = "Boo! 👻"
        let s = Socket(socketDescriptor: sds[0])
        _ = try! Strand {
            do {
                try s.send(sendableData)
            } catch let error {
                XCTFail("Unable to send data to socket due to error: \(error)")
            }
        }

        let data = try! readDataFromSocket(sds[1])

        let stringData = String(utf8: data)
        XCTAssertEqual(sendableData, stringData)
    }

    func testReceivingRawDataToSocket_readsCorrectly() {
        var sds: [Int32] = [0,0]

        if socketpair(AF_UNIX, Hummingbird.sockStream, 0, &sds) == -1 {
            XCTFail("Unable to create socket pair")
            return
        }

        let sendableData = [2, 5, 10] as [UInt8]

        _ = try! Strand {
            do {
                try self.sendData(sendableData, toSocket: sds[0])
            } catch let error {
                XCTFail("Unable to send data to socket due to error: \(error)")
            }
        }

        let s = Socket(socketDescriptor: sds[1])
        let data: [UInt8] = try! s.receive()

        XCTAssertEqual(data, sendableData)
    }

    func testReceivingStringDataToSocket_readsCorrectly() {
        var sds: [Int32] = [0,0]

        if socketpair(AF_UNIX, Hummingbird.sockStream, 0, &sds) == -1 {
            XCTFail("Unable to create socket pair")
            return
        }

        let sendableData = "Boo! 👻"

        _ = try! Strand {
            do {
                try self.sendData(sendableData.utf8.map({ $0 as UInt8 }), toSocket: sds[0])
            } catch let error {
                XCTFail("Unable to send data to socket due to error: \(error)")
            }
        }

        let s = Socket(socketDescriptor: sds[1])
        let data: String = try! s.receive()
        XCTAssertEqual(data, sendableData)
    }

    func testBind_bindsCorrectly() {
        do {
            let s = try Socket.streamSocket()
            try s.bind("0.0.0.0", port: "29876")
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBind_withInvalidAddress_throwsCorrectException() {
        do {
            let s = try Socket.streamSocket()
            try s.bind("derpity&^#@derp!@", port: "29876")
            XCTFail("Expected binding to fail")
        } catch let error as SocketError {
            switch error {
            case .BindingFailed(_, _): break
            default: XCTFail("Unexpected error: \(error)")
            }
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBind_withInvalidPort_throwsCorrectException() {
        do {
            let s = try Socket.streamSocket()
            try s.bind("0.0.0.0", port: "derpadee")
            XCTFail("Expected binding to fail")
        } catch let error as SocketError {
            switch error {
            case .InvalidPort: break
            default: XCTFail("Unexpected error: \(error)")
            }
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func readDataFromSocket(socket: Int32) throws -> [UInt8] {
        let buffer = UnsafeMutablePointer<UInt8>.alloc(1024)

        defer { buffer.dealloc(1024) }

        let bytesRead = systemRecv(socket, buffer, 1024, 0)
        if bytesRead == -1 {
            throw SocketError.ReceiveFailed(code: Int(errno), message: String.fromCString(strerror(errno)))
        }

        guard bytesRead != 0 else { return [] }

        var readData = [UInt8]()
        for i in 0 ..< bytesRead {
            readData.append(buffer[i])
        }

        return readData
    }

    private func sendData(data: [UInt8], toSocket socket: Int32) throws {
        #if os(Linux)
            let flags = Int32(MSG_NOSIGNAL)
        #else
            let flags = Int32(0)
        #endif

        systemSend(socket, data, data.count, flags)
    }
}
