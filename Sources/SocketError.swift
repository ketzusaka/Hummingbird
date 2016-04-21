//
//  SocketError.swift
//  Hummingbird
//
//  Created by James Richard on 4/21/16.
//
//

#if !swift(>=3.0)
    public typealias ErrorProtocol = ErrorType
#endif

public enum SocketError: ErrorProtocol {
    case acceptConsecutivelyFailing(code: Int, message: String?)
    case bindingFailed(code: Int, message: String?)
    case bufferReadFailed
    case closeFailed(code: Int, message: String?)
    case connectionClosedByPeer
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
    case stringTranscodingFailed
    case failedToGetIPFromHostname(code: Int, message: String?)
}

extension SocketError: Equatable { }

public func == (lhs: SocketError, rhs: SocketError) -> Bool {
    switch (lhs, rhs) {
    case (let .acceptConsecutivelyFailing(lCode, lMessage), let .acceptConsecutivelyFailing(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .bindingFailed(lCode, lMessage), let .bindingFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .listenFailed(lCode, lMessage), let .listenFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .receiveFailed(lCode, lMessage), let .receiveFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .connectFailed(lCode, lMessage), let .connectFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .obtainingAddressInformationFailed(lCode, lMessage), let .obtainingAddressInformationFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .socketCreationFailed(lCode, lMessage), let .socketCreationFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .socketConfigurationFailed(lCode, lMessage), let .socketConfigurationFailed(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .failedToGetIPFromHostname(lCode, lMessage), let .failedToGetIPFromHostname(rCode, rMessage)):
        return lCode == rCode && lMessage == rMessage
    case (let .sendFailed(lCode, lMessage, lSent), let .sendFailed(rCode, rMessage, rSent)):
        return lCode == rCode && lMessage == rMessage && lSent == rSent
    case (let .hostInformationIncomplete(lMessage), let .hostInformationIncomplete(rMessage)):
        return lMessage == rMessage
    case (.bufferReadFailed, .bufferReadFailed):
        return true
    case (.connectionClosedByPeer, .connectionClosedByPeer):
        return true
    case (.invalidData, .invalidData):
        return true
    case (.stringTranscodingFailed, .stringTranscodingFailed):
        return true
    default:
        return false
    }
}
