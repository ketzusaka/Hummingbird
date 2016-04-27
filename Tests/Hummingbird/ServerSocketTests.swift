//
//  ServerSocketTests.swift
//  Hummingbird
//
//  Created by James Richard on 4/20/16.
//
//

@testable import Hummingbird
import Strand
import XCTest

#if os(Linux)
    import Glibc
#else
    import Darwin.C
#endif

#if os(Linux)
    extension ServerSocketTests {
        static var allTests : [(String, SocketTests -> () throws -> Void)] {
            return [
                       ("testBind_withInvalidAddress_throwsCorrectException", testBind_withInvalidAddress_throwsCorrectException),
                       ("testBind_withInvalidPort_throwsCorrectException", testBind_withInvalidPort_throwsCorrectException),
                       ("testBind_bindsCorrectly", testBind_bindsCorrectly)
            ]
        }
    }
#endif

class ServerSocketTests: XCTestCase {
    func testBind_bindsCorrectly() {
        do {
            let s = try ServerSocket(address: "0.0.0.0", port: "29876")
            try s.bind()
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBind_withInvalidAddress_throwsCorrectException() {
        do {
            let s = try ServerSocket(address: "derpity&^#@derp!@", port: "29876")
            try s.bind()
            XCTFail("Expected binding to fail")
        } catch let error as SocketError {
            switch error {
            case .bindingFailed(_, _): break
            default: XCTFail("Unexpected error: \(error)")
            }
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testBind_withInvalidPort_throwsCorrectException() {
        do {
            let s = try ServerSocket(address: "0.0.0.0", port: "derpadee")
            try s.bind()
            XCTFail("Expected binding to fail")
        } catch let error as SocketError {
            switch error {
            case .invalidPort: break
            default: XCTFail("Unexpected error: \(error)")
            }
        } catch let error {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
