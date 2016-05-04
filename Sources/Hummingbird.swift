//
//  Hummingbird.swift
//  Hummingbird
//
//  Created by James Richard on 4/20/16.
//
//

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
