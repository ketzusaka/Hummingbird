//
//  String+Transcoding.swift
//  Hummingbird
//
//  Created by James Richard on 2/26/16.
//  Copyright © 2016 MagicalPenguin. All rights reserved.
//

import Foundation

// Credit to Mike Ash: https://www.mikeash.com/pyblog/friday-qa-2015-11-06-why-is-swifts-string-api-so-hard.html
extension String {
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
}