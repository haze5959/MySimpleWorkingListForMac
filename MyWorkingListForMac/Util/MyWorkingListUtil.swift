//
//  MyWorkingListUtil.swift
//  MyWorkingListForMac
//
//  Created by OQ on 09/04/2019.
//  Copyright © 2019 OQ. All rights reserved.
//

import Foundation

class MyWorkingListUtil {
    
    // MARK: - Time to String
    static func transformTimeToString(time: Int) -> String {
        var timeVal = time
        if timeVal > 60 {   //mintue
            timeVal = timeVal/60
            
            if timeVal > 60 {   //hour
                timeVal = timeVal/60
                
                if timeVal > 24 {   //day
                    timeVal = timeVal/24
                    
                    if timeVal > 30 {   //month
                        timeVal = timeVal/30
                        
                        if timeVal > 12 {   //year
                            timeVal = timeVal/12
                            return "\(timeVal) years ago.."
                        }
                        return "\(timeVal) months ago.."
                    }
                    return "\(timeVal) days ago.."
                }
                return "\(timeVal) hours ago.."
            }
            return "\(timeVal) minutes ago.."
        }
        
        return "Now"
    }
}
