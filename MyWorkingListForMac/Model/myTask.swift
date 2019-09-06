//
//  task.swift
//  MyWorkingList
//
//  Created by OQ on 2018. 7. 3..
//  Copyright © 2018년 OQ. All rights reserved.
//

import Cocoa

class myTask: NSObject {
    let index:Int!
    let id:String!
    let date:Date!
    var body:String!
    
    init(_ index:Int, _ id:String, _ dateVal:Date, _ bodyVal:String) {
        self.index = index
        self.id = id
        self.body = bodyVal
        self.date = dateVal
    }
}
