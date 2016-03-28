#if os(Linux)
import XCTest
@testable import HummingbirdTestSuite

XCTMain([
	testCase(SocketTests.allTests)
])
#endif
