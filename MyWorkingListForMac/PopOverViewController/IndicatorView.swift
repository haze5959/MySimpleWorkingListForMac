//
//  IndicatorView.swift
//  MyWorkingListForMac
//
//  Created by OQ on 21/10/2018.
//  Copyright © 2018 OQ. All rights reserved.
//

import Cocoa

class IndicatorView: NSView {

    let indicator = NSProgressIndicator.init()
    let backgroundColor = NSColor.init(red: 0, green: 0, blue: 0, alpha: 0.3)

    
    override init(frame frameRect: NSRect) {
        super.init(frame:frameRect);
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)!
        
        indicator.style = .spinning
        indicator.controlSize = .regular
        indicator.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(indicator)
        indicator.widthAnchor.constraint(lessThanOrEqualToConstant: 30).isActive = true
        indicator.heightAnchor.constraint(lessThanOrEqualToConstant: 30).isActive = true
        indicator.centerXAnchor.constraint(equalTo: self.centerXAnchor).isActive = true
        indicator.centerYAnchor.constraint(equalTo: self.centerYAnchor).isActive = true
        
    }
    
    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
    }
    
    func start() -> Void {
        DispatchQueue.main.async {
            self.isHidden = false
            self.indicator.startAnimation(nil)
        }
    }
    
    func stop() -> Void {
        DispatchQueue.main.async {
            self.isHidden = true
            self.indicator.stopAnimation(nil)
        }
    }
}
