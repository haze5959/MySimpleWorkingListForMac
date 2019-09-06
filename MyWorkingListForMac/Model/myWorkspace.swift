//
//  myWorkspace.swift
//  MyWorkingList
//
//  Created by 권오규 on 2018. 7. 6..
//  Copyright © 2018년 OQ. All rights reserved.
//
import Cocoa

public enum DateType: Int, CaseIterable {
    case day = 0
    case week
    case month
}

class myWorkspace: NSObject {
    let id:String!
    let name:String!
    let dateType:DateType!
    var pivotDate:Date!
    
//    init(id:String, name:String) {
//        self.id = id;
//        self.name = name;
//    }
    
    init(id:String, name:String, dateType:DateType, pivotDate:Date?) {
        self.id = id;
        self.name = name;
        self.dateType = dateType
        self.pivotDate = pivotDate;
    }
}
