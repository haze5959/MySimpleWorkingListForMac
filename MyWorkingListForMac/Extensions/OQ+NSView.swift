//
//  OQ+NSView.swift
//  MyWorkingListForMac
//
//  Created by OGyu kwon on 09/09/2019.
//  Copyright © 2019 OQ. All rights reserved.
//

import Cocoa

extension NSView {
    var isDarkMode: Bool {
        if #available(OSX 10.14, *) {
            if effectiveAppearance.name == .darkAqua {
                return true
            }
        }
        return false
    }
}
