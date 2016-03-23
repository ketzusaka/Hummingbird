//
//  String+Transcoding.swift
//  Hummingbird
//
//  Created by James Richard on 2/26/16.
//

// Credit to Mike Ash: https://www.mikeash.com/pyblog/friday-qa-2015-11-06-why-is-swifts-string-api-so-hard.html
extension String {
    #if swift(>=3.0)
    init?<Seq: Sequence where Seq.Iterator.Element == UInt16>(utf16: Seq) {
        self.init()
        guard !transcode(utf16.makeIterator(), from: UTF16.self, to: UTF32.self, stoppingOnError: true, sendingOutputTo: { self.append(UnicodeScalar($0)) }) else { return nil }
    }

    init?<Seq: Sequence where Seq.Iterator.Element == UInt8>(utf8: Seq) {
        self.init()
        guard !transcode(utf8.makeIterator(), from: UTF8.self, to: UTF32.self, stoppingOnError: true, sendingOutputTo: { self.append(UnicodeScalar($0)) }) else { return nil }
    }
    #else
    init?<Seq: SequenceType where Seq.Generator.Element == UInt16>(utf16: Seq) {
        self.init()

        guard transcode(UTF16.self,
                        UTF32.self,
                        utf16.generate(),
                        { self.append(UnicodeScalar($0)) },
                        stopOnError: true)
            == false else { return nil }
    }

    init?<Seq: SequenceType where Seq.Generator.Element == UInt8>(utf8: Seq) {
        self.init()

        guard transcode(UTF8.self,
                        UTF32.self,
                        utf8.generate(),
                        { self.append(UnicodeScalar($0)) },
                        stopOnError: true)
            == false else { return nil }
    }
    #endif
}
