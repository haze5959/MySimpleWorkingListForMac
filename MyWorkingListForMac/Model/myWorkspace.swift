//
//  myWorkspace.swift
//  MyWorkingList
//
//  Created by 권오규 on 2018. 7. 6..
//  Copyright © 2018년 OQ. All rights reserved.
//
import Cocoa

class myWorkspace: NSObject {
    let id:String!;
    let name:String!;
    var pivotDate:Date!;
    
//    init(id:String, name:String) {
//        self.id = id;
//        self.name = name;
//    }
    
    init(id:String, name:String, pivotDate:Date) {
        self.id = id;
        self.name = name;
        self.pivotDate = pivotDate;
    }
}
