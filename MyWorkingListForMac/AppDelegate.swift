//
//  AppDelegate.swift
//  MyWorkingListForMac
//
//  Created by OQ on 2018. 9. 9..
//  Copyright © 2018년 OQ. All rights reserved.
//

import Cocoa
import Magnet
import CloudKit

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    static let CLOUD_SYNC_TIME = "CloudSyncTime"
    
    var container: CKContainer!
    var privateDB: CKDatabase!
    var eventMonitor: EventMonitor? //to detect click in outside
    
    let statusItem:NSStatusItem  = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    public let popover = NSPopover()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("[AppDelegate] MyWorkingList App start!!")
        
        //get instance statusBar and set Btn
        if let button = self.statusItem.button {
            button.image = NSImage(named:NSImage.Name("StatusBar"))
            button.action = #selector(togglePopover(_:))
        }
        
        self.popover.contentViewController = SharedData.instance.popOverVC

        //detect click in outside
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let strongSelf = self, strongSelf.popover.isShown {
                strongSelf.closePopover(sender: event)
            }
        }
        
        //setting hot key
        if let hotKeyToOpenData = UserDefaults.standard.object(forKey: SettingViewController.HOTKEY_OPEN) as? Data {
            if let hotKeyToOpen = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToOpenData) {
                let hotKey = HotKey(identifier: SettingViewController.HOTKEY_OPEN, keyCombo: hotKeyToOpen, target: self, action: #selector(hotkeyCalled))
                hotKey.register()
            }
        
        } else {
            //default shortcut key
            let keyCombo = KeyCombo(doubledCocoaModifiers: .shift)
            let hotKey = HotKey(identifier: SettingViewController.HOTKEY_OPEN, keyCombo: keyCombo!, target: self, action: #selector(hotkeyCalled))
            hotKey.register()

            if let encoded = try? JSONEncoder().encode(keyCombo) {
                UserDefaults.standard.set(encoded, forKey: SettingViewController.HOTKEY_OPEN)
            }
        }
        
        self.initCloud()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    // MARK: StatusBar Btn Evnet
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender: sender)
        } else {
            showPopover(sender: sender)
        }
    }
    
    func showPopover(sender: Any?) {
        if let button = statusItem.button {
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            self.eventMonitor?.start()
        }
    }
    
    func closePopover(sender: Any?) {
        self.popover.performClose(sender)
        self.eventMonitor?.stop()
    }
    
    @objc func hotkeyCalled() {
        print("[AppDelegate] HotKey called!!!!")
        togglePopover(nil)
    }
    
    // MARK: Open dialog
    func openTwoBtnDialogOKCancel(question: String, text: String) -> Void
    {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = text
            alert.alertStyle = NSAlert.Style.warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")
            alert.runModal()
        }
    }
    
    func openOneBtnDialogOK(question: String, text: String) -> Void
    {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = text
            alert.alertStyle = NSAlert.Style.warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
}

extension AppDelegate {
    func initCloud() -> Void {
        //iCloud 권한 체크
        CKContainer.init(identifier: "iCloud.com.oq.MyWorkingList").accountStatus{ status, error in
            guard status == .available else {
                self.openOneBtnDialogOK(question: "user’s iCloud is not available", text: "Quit the app.")
                return
            }
            //The user’s iCloud account is available..
            
            self.container = CKContainer.init(identifier: "iCloud.com.oq.MyWorkingList");
            self.privateDB = self.container.privateCloudDatabase;
            
            let predicate = NSPredicate(value: true);
            let query = CKQuery(recordType: "workSpace", predicate: predicate);
            
            self.privateDB.perform(query, inZoneWith: nil) { records, error in
                guard error == nil else {
                    print("err: \(String(describing: error))");
                    self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Quit the app.")
                    return;
                }
                
                if records?.count == 0 {    //최초 실행
                    self.makeWorkSpace(workSpaceName: "default");
                    
                } else {
                    let sharedData = SharedData.instance;
                    
                    var isSameValue = false; //클라우드 데이터에 디바이스 값이 들어있는지 판별
                    for record in records!{
                        let value:String = record.value(forKey: "name") as! String;
                        sharedData.workSpaceArr.append(myWorkspace.init(id:record.recordID.recordName, name:record.value(forKey: "name") as! String));
                        
                        if value == sharedData.seletedWorkSpace?.name {  //디바이스에 저장된 값과 클라우드에서 가져온 값이 일치한다면
                            isSameValue = true;
                        }
                    }
                    
                    if !isSameValue {
                        let workSpace = myWorkspace.init(id:(records![0].recordID.recordName) , name:records![0].value(forKey: "name") as! String);
                        sharedData.seletedWorkSpace = workSpace;
                        UserDefaults().set(workSpace.id, forKey: "seletedWorkSpaceId");
                        UserDefaults().set(workSpace.name, forKey: "seletedWorkSpaceName");
                    }
                    
                    NotificationCenter.default.post(name: .showProgress, object: nil)
                    sharedData.workSpaceUpdateObserver?.onNext(sharedData.seletedWorkSpace!);
                }
                
                //클라우드 변경사항 노티 적용
                self.saveSubscription()
            }
        }
    }
    
    // MARK: ==============================
    // MARK: CloudKit 메서드
    // 워크스페이스 생성
    func makeWorkSpace(workSpaceName:String) -> Void {
        //******클라우드에 새 워크스페이즈 저장******
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let record = CKRecord(recordType: "workSpace")
        record.setValue(workSpaceName, forKey: "name")
        self.privateDB.save(record) { savedRecord, error in
            //해당 데이터를 워크스페이스 보관 배열에 넣는다.
            let workSpace = myWorkspace.init(id: (savedRecord?.recordID.recordName)!, name: savedRecord?.value(forKey: "name") as! String);
            UserDefaults().set(workSpace.id, forKey: "seletedWorkSpaceId");
            UserDefaults().set(workSpace.name, forKey: "seletedWorkSpaceName");
            SharedData.instance.workSpaceArr.append(workSpace);
            SharedData.instance.seletedWorkSpace = workSpace;
            
            NotificationCenter.default.post(name: .closeProgress, object: nil)
            
            SharedData.instance.workSpaceUpdateObserver?.onNext(workSpace);
        }
        //***********************************
    }
    
    // 워크스페이스 수정
    func updateWorkSpace(recordId:String, newName:String) -> Void {
        //******클라우드에 워크스페이즈 수정******
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let recordId = CKRecord.ID(recordName: recordId)
        self.privateDB.fetch(withRecordID: recordId) { updatedRecord, error in
            if error != nil {
                return
            }
            
            updatedRecord?.setObject(newName as CKRecordValue, forKey: "name");
            self.privateDB.save(updatedRecord!) { savedRecord, error in
                NotificationCenter.default.post(name: .closeProgress, object: nil)
            }
        }
        //***********************************
    }
    
    // 테스크 가져오기
    func getDayTask(startDate:Date, endDate:Date?, workSpaceId:String) -> Void {
        NotificationCenter.default.post(name: .showProgress, object: nil)
        
        let startDateAddDay = startDate.addingTimeInterval(-86400.0);
        
        var predicate = NSPredicate(format: "workSpaceId = %@ AND date >= %@", workSpaceId, startDateAddDay as NSDate);
        if endDate != nil {
            let endDateAddDay = endDate?.addingTimeInterval(86400.0);
            predicate = NSPredicate(format: "workSpaceId = %@ AND date >= %@ AND date <= %@", workSpaceId, startDateAddDay as NSDate, endDateAddDay! as NSDate);
        }
        
        let query = CKQuery(recordType: "dayTask", predicate: predicate);
        
        self.privateDB.perform(query, inZoneWith: nil) { records, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Quit the app.")
                return;
            }
            
            let dateFormatter = DateFormatter();
            dateFormatter.setLocalizedDateFormatFromTemplate("yyMMdd");
            
            for record in records!{
                let body:String = record.value(forKey: "body") as! String;
                let title:String = record.value(forKey: "title") as! String;
                let date:Date = record.value(forKey: "date") as! Date;
                
                let task:myTask = myTask.init(record.recordID.recordName, date, body, title);
                let dayKey:String = dateFormatter.string(from: task.date);
                
                SharedData.instance.taskAllDic.setValue(task, forKey: dayKey);
            }
            
            SharedData.instance.popViewContrllerDelegate.reloadTableAll();
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDelegate.CLOUD_SYNC_TIME)
            NotificationCenter.default.post(name: .closeProgress, object: nil)
        };
    }
    
    // 테스크 생성
    func makeDayTask(workSpaceId:String, taskDate:Date, taskBody:String, taskTitle:String?, index:Int) -> Void {
        //*********클라우드에 새 테스크 저장*********
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let record = CKRecord(recordType: "dayTask");
        record.setValue(workSpaceId, forKey: "workSpaceId");
        record.setValue(taskDate, forKey: "date");
        record.setValue(taskBody, forKey: "body");
        record.setValue(taskTitle, forKey: "title");
        self.privateDB.save(record) { savedRecord, error in
            //해당 데이터를 워크스페이스 보관 배열에 넣는다.
            let task = myTask.init((savedRecord?.recordID.recordName)!, savedRecord?.value(forKey: "date") as! Date, savedRecord?.value(forKey: "body") as! String, savedRecord?.value(forKey: "title") as? String);
            
            let dateFormatter = DateFormatter();
            dateFormatter.setLocalizedDateFormatFromTemplate("yyMMdd");
            let dayKey:String = dateFormatter.string(from: task.date);
            
            SharedData.instance.taskAllDic.setValue(task, forKey: dayKey);
            
            NotificationCenter.default.post(name: .closeProgress, object: nil)
            
            SharedData.instance.popViewContrllerDelegate.reloadTableWithUpdateCell(index: index, title: taskTitle!, body: taskBody)
        }
        //***********************************
    }
    
    // 테스크 수정
    func updateDayTask(task:myTask, index:Int) -> Void {
        //*********클라우드에 테스크 수정*********
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let recordId = CKRecord.ID(recordName: task.id)
        self.privateDB.fetch(withRecordID: recordId) { updatedRecord, error in
            if error != nil {
                return
            }
            
            if task.title != nil {
                updatedRecord?.setObject(task.title! as CKRecordValue, forKey: "title");
            }
            
            updatedRecord?.setObject(task.body as CKRecordValue, forKey: "body");
            self.privateDB.save(updatedRecord!) { savedRecord, error in
                NotificationCenter.default.post(name: .closeProgress, object: nil)
                
                SharedData.instance.popViewContrllerDelegate.reloadTableWithUpdateCell(index: index, title: task.title!, body: task.body);
            }
        }
        //***********************************
    }
    
    //해당 리코드 삭제
    func deleteRecord(recordId:String) -> Void {
        //********클라우드 워크스페이스 삭제********
        NotificationCenter.default.post(name: .showProgress, object: nil)
        
        //일일 테스트 먼저 삭제
        let predicate = NSPredicate(format: "workSpaceId = %@", recordId);
        let query = CKQuery(recordType: "dayTask", predicate: predicate);
        
        self.privateDB.perform(query, inZoneWith: nil) { records, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Quit the app.")
                return;
            }
            
            let dateFormatter = DateFormatter();
            dateFormatter.setLocalizedDateFormatFromTemplate("yyMMdd");
            
            let dispatchGroup = DispatchGroup()
            for record in records!{
                DispatchQueue(label: "kr.myWorkingList.deleteRecord").async(group: dispatchGroup) {
                    self.privateDB.delete(withRecordID: record.recordID) { deletedRecordId, error in
                        guard error == nil else {
                            print("err: \(String(describing: error))");
                            self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Quit the app.")
                            return;
                        }
                    }
                }
            }
            
            dispatchGroup.notify(queue: DispatchQueue.main) {
                //워크스페이스 삭제
                let recordId = CKRecord.ID(recordName: recordId)
                self.privateDB.delete(withRecordID: recordId) { deletedRecordId, error in
                    guard error == nil else {
                        print("err: \(String(describing: error))");
                        self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Quit the app.")
                        return;
                    }
                    
                    print("delete complete!")
                    SharedData.instance.popViewContrllerDelegate.reloadTableAll();
                    
                    NotificationCenter.default.post(name: .closeProgress, object: nil)
                }
            }
        };
        
        //***********************************
    }
    // MARK: ==============================
    
    // MARK: - Notification related cloud
    public func saveSubscription() {
        // RecordType specifies the type of the record
        let subscriptionID = "cloudkit-recordType-changes"
        // Let's keep a local flag handy to avoid saving the subscription more than once.
        // Even if you try saving the subscription multiple times, the server doesn't save it more than once
        // Nevertheless, let's save some network operation and conserve resources
        let subscriptionSaved = UserDefaults.standard.bool(forKey: subscriptionID)
        guard !subscriptionSaved else {
            return
        }
        
        // Subscribing is nothing but saving a query which the server would use to generate notifications.
        // The below predicate (query) will raise a notification for all changes.
        let predicate = NSPredicate(value: true)
        let subscription = CKQuerySubscription(recordType: "dayTask",
                                               predicate: predicate,
                                               subscriptionID: subscriptionID,
                                               options: [.firesOnRecordCreation, .firesOnRecordDeletion, .firesOnRecordUpdate])
        
        let notificationInfo = CKSubscription.NotificationInfo()
        // Set shouldSendContentAvailable to true for receiving silent pushes
        // Silent notifications are not shown to the user and don’t require the user's permission.
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        
        // Use CKModifySubscriptionsOperation to save the subscription to CloudKit
        let operation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: [])
        operation.modifySubscriptionsCompletionBlock = { (_, _, error) in
            guard error == nil else {
                return
            }
            UserDefaults.standard.set(true, forKey: subscriptionID)
        }
        
        // Add the operation to the corresponding private or public database
        self.privateDB.add(operation)
    }
    
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        // Whenever there's a remote notification, this gets called
        print("[AppDelegate] remote notification call!!")
        
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if (notification.subscriptionID == "cloudkit-recordType-changes") {
            print("[CLOUD UPDATE] notification - \(notification)")
            SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!) //일정 업데이트
        }
    }
}
