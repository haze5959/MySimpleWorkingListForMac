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
import StoreKit
import RxSwift
import RxCocoa
import ServiceManagement

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    static let CLOUD_SYNC_TIME = "CloudSyncTime"
    
    var container: CKContainer!
    var privateDB: CKDatabase!
//    var eventMonitor: EventMonitor? //to detect click in outside
    
    let statusItem:NSStatusItem  = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    public let popover = NSPopover()
    
    public let updateWaitingTask = BehaviorRelay<myTask?>(value: nil)
    let disposeBag = DisposeBag()
    
    var reviewTimer: Timer?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        print("[AppDelegate] MyWorkingList App start!!")
        NSApp.registerForRemoteNotifications(matching: .badge)// silent push notification!
        
        //get instance statusBar and set Btn
        if let button = self.statusItem.button {
            button.image = NSImage(named:NSImage.Name("StatusBar"))
            button.action = #selector(togglePopover(_:))
        }
        
        self.popover.contentViewController = SharedData.instance.popOverVC

        //detect click in outside
//        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
//            if let strongSelf = self,
//                strongSelf.popover.isShown,
//                let contentVC = strongSelf.popover.contentViewController,
//                let event = event {
//                if !contentVC.view.frame.contains(event.locationInWindow) {
//                    strongSelf.closePopover(sender: event)
//                }
//            }
//
//            return event
//        }
        
        //setting hot key
        //open popover hot key
        if let hotKeyToOpenData = UserDefaults.standard.object(forKey: hotKeyEnum.HOTKEY_OPEN.rawValue) as? Data {
            if let hotKeyToOpen = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToOpenData) {
                let hotKey = HotKey(identifier: hotKeyEnum.HOTKEY_OPEN.rawValue, keyCombo: hotKeyToOpen, target: self, action: #selector(hotkeyOpenCalled))
                hotKey.register()
            }
        
        }
        
        //refresh hot key
        if let hotKeyToRefreshData = UserDefaults.standard.object(forKey: hotKeyEnum.HOTKEY_REFRESH.rawValue) as? Data {
            if let hotKeyToRefresh = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToRefreshData) {
                let hotKey = HotKey(identifier: hotKeyEnum.HOTKEY_REFRESH.rawValue, keyCombo: hotKeyToRefresh, target: self, action: #selector(hotkeyRefreshCalled))
                hotKey.register()
            }
        }
        
        self.initCloud()
        self.initUpdateTaskObserver()
        
        self.showReviewTimer(second: 3600)
        self.manageLauncherApp()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.buyComplete),
                                               name: .IAPHelperPurchaseNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(calendarDayDidChange),
                                               name:NSNotification.Name.NSCalendarDayChanged,
                                               object:nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    func initUpdateTaskObserver() {
        self.updateWaitingTask
            .asObservable()
            .subscribeOn(SerialDispatchQueueScheduler(qos: .background))
            .subscribe { (event) in
                guard let taskOptional = event.element else {
                    print("No element!!")
                    return
                }
                
                guard let task = taskOptional else {
                    print("No task!!")
                    return
                }
                
                if task.id == nil || task.id == "" {    //새로 저장
                    //******클라우드에 새 메모 저장******
                    self.makeDayTask(workSpaceId: (SharedData.instance.seletedWorkSpace?.id)!, taskDate: task.date, taskBody: task.body, index: task.index)
                    //***********************************
                } else { //기존 수정
                    //******클라우드에 매모 수정******
                    self.updateDayTask(task: task)
                    //***********************************
                }
            }.disposed(by: self.disposeBag)
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
//            self.eventMonitor?.start()
            self.popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
            SharedData.instance.popOverVC.pinBtn.image = #imageLiteral(resourceName: "pin_white")
        }
    }
    
    func closePopover(sender: Any?) {
//        self.eventMonitor?.stop()
        self.popover.performClose(sender)
    }
    
    @objc func hotkeyOpenCalled() {
        print("[AppDelegate] HotKey Open called!!!!")
        togglePopover(nil)
    }
    
    @objc func hotkeyRefreshCalled() {
        print("[AppDelegate] HotKey Refresh called!!!!")
        if popover.isShown {
            if SharedData.instance.popOverVC.shouldUpdate {  //셀 업데이트
                SharedData.instance.popOverVC.updateSelectedRow()
            } else {    //테이블 데이터 업데이트
                SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
            }
        }
    }
    
    // MARK: Open dialog
    func openTwoBtnDialogOKCancel(message: String, informativeText: String, icon: NSImage? = nil, leftBtnTitle: String = "OK", rightBtnTitle: String = "Cancel", _ completion: @escaping (_ response: NSApplication.ModalResponse) -> Void) -> Void
    {
        DispatchQueue.main.async {
            let alert = NSAlert()
            if let icon = icon {
                alert.icon = icon
            }
            
            alert.messageText = message
            alert.informativeText = informativeText
            alert.alertStyle = NSAlert.Style.informational
            alert.addButton(withTitle: leftBtnTitle)
            alert.addButton(withTitle: rightBtnTitle)
            let response = alert.runModal()
            completion(response)
        }
    }
    
    func openOneBtnDialogOK(question: String, text: String, _ completion: @escaping () -> Void) -> Void
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
                self.openOneBtnDialogOK(question: "user’s iCloud is not available\nThis might happen if the user is not logged into iCloud. Please check out this post: https://support.apple.com/en-us/HT208682#macos", text: "Quit the app.", {
                    NSApplication.shared.terminate(self)    //Quit App
                })
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
                    self.openOneBtnDialogOK(question: "iCloud connection is unstable.\nThis might happen if the user is not logged into iCloud. Please check out this post: https://support.apple.com/en-us/HT208682#macos", text: "Quit the app.", {
                        NSApplication.shared.terminate(self)    //Quit App
                    })
                    return;
                }
                
                if records?.count == 0 {    //최초 실행
                    self.makeWorkSpace(workSpaceName: "default",dateType: .day)
                    
                } else {
                    let sharedData = SharedData.instance;
                    
                    var isSameValue = false; //클라우드 데이터에 디바이스 값이 들어있는지 판별
                    for record in records!{
                        let name:String = record.value(forKey: "name") as! String;
                        let workSpaceDateType = record.value(forKey: "dateType") as! Int
                        sharedData.workSpaceArr.append(myWorkspace.init(id:record.recordID.recordName, name:name, dateType: DateType(rawValue: workSpaceDateType)!, pivotDate: Date()));
                        
                        if name == sharedData.seletedWorkSpace?.name {  //디바이스에 저장된 값과 클라우드에서 가져온 값이 일치한다면
                            isSameValue = true;
                        }
                    }
                    
                    if !isSameValue {
                        let workSpaceDateType = records![0].value(forKey: "dateType") as! Int
                        let workSpace = myWorkspace.init(id:(records![0].recordID.recordName) , name:records![0].value(forKey: "name") as! String, dateType: DateType(rawValue: workSpaceDateType)!, pivotDate: Date());
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
    func makeWorkSpace(workSpaceName:String, dateType:DateType) -> Void {
        //******클라우드에 새 워크스페이즈 저장******
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let record = CKRecord(recordType: "workSpace")
        record.setValue(workSpaceName, forKey: "name")
        record.setValue(dateType.rawValue, forKey: "dateType")
        
        self.privateDB.save(record) { savedRecord, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.makeWorkSpace(workSpaceName: workSpaceName, dateType: dateType)
                })
                return;
            }
            
            //해당 데이터를 워크스페이스 보관 배열에 넣는다.
            let workSpaceDateType = record.value(forKey: "dateType") as! Int
            let workSpace = myWorkspace.init(id: (savedRecord?.recordID.recordName)!, name: savedRecord?.value(forKey: "name") as! String, dateType: DateType(rawValue: workSpaceDateType)!, pivotDate: Date());
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
        let recordIdObject = CKRecord.ID(recordName: recordId)
        self.privateDB.fetch(withRecordID: recordIdObject) { updatedRecord, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.updateWorkSpace(recordId: recordId, newName: newName)
                })
                return;
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
        
        let startDateAddDay = startDate.addingTimeInterval(-86400.0)
        
        var predicate = NSPredicate(format: "workSpaceId = %@ AND date >= %@", workSpaceId, startDateAddDay as NSDate)
        if endDate != nil {
            let endDateAddDay = endDate?.addingTimeInterval(86400.0);
            predicate = NSPredicate(format: "workSpaceId = %@ AND date >= %@ AND date <= %@", workSpaceId, startDateAddDay as NSDate, endDateAddDay! as NSDate)
        }
        
        let query = CKQuery(recordType: "dayTask", predicate: predicate)
        
        self.privateDB.perform(query, inZoneWith: nil) { records, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.getDayTask(startDate: startDate, endDate: endDate, workSpaceId: workSpaceId)
                })
                return
            }
            
            for record in records! {
                let body:String = record.value(forKey: "body") as! String
                let date:Date = record.value(forKey: "date") as! Date
                
                let task:myTask = myTask(-1, record.recordID.recordName, date, body)
                let dayKey:String = DateFormatter.localizedString(from: task.date, dateStyle: .short, timeStyle: .none)
                
                SharedData.instance.taskAllDic.setValue(task, forKey: dayKey)
            }
            
            SharedData.instance.popViewContrllerDelegate.reloadTableAll()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: AppDelegate.CLOUD_SYNC_TIME)
            
            SharedData.instance.popViewContrllerDelegate.setRefreshTimeLabel(text: MyWorkingListUtil.transformTimeToString(time: 0))
            NotificationCenter.default.post(name: .closeProgress, object: nil)
        };
    }
    
    // 테스크 생성
    func makeDayTask(workSpaceId:String, taskDate:Date, taskBody:String, index:Int) -> Void {
        //*********클라우드에 새 테스크 저장*********
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let record = CKRecord(recordType: "dayTask");
        record.setValue(workSpaceId, forKey: "workSpaceId");
        record.setValue(taskDate, forKey: "date");
        record.setValue(taskBody, forKey: "body");
        self.privateDB.save(record) { savedRecord, error in
            guard error == nil else {
                print("err: \(String(describing: error))")
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.makeDayTask(workSpaceId: workSpaceId, taskDate: taskDate, taskBody: taskBody, index: index)
                })
                return
            }
            
            //해당 데이터를 워크스페이스 보관 배열에 넣는다.
            let task = myTask(index, (savedRecord?.recordID.recordName)!, savedRecord?.value(forKey: "date") as! Date, savedRecord?.value(forKey: "body") as! String)
            
            let dayKey:String = DateFormatter.localizedString(from: task.date, dateStyle: .short, timeStyle: .none)
            
            SharedData.instance.taskAllDic.setValue(task, forKey: dayKey)
            
            NotificationCenter.default.post(name: .closeProgress, object: nil)
            
            SharedData.instance.popViewContrllerDelegate.reloadTableWithUpdateCell(index: index, body: taskBody)
//            SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
        }
        //***********************************
    }
    
    // 테스크 수정
    func updateDayTask(task:myTask) -> Void {
        //*********클라우드에 테스크 수정*********
        NotificationCenter.default.post(name: .showProgress, object: nil)
        let recordId = CKRecord.ID(recordName: task.id)
        self.privateDB.fetch(withRecordID: recordId) { updatedRecord, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.updateDayTask(task: task)
                })
                return;
            }
            
            updatedRecord?.setObject(task.body as CKRecordValue, forKey: "body");
            self.privateDB.save(updatedRecord!) { savedRecord, error in
                NotificationCenter.default.post(name: .closeProgress, object: nil)
                
                SharedData.instance.popViewContrllerDelegate.reloadTableWithUpdateCell(index: task.index, body: task.body);
//                SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
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
                self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.deleteRecord(recordId: recordId)
                })
                return;
            }
            
            let dispatchGroup = DispatchGroup()
            for record in records!{
                DispatchQueue(label: "kr.myWorkingList.deleteRecord").async(group: dispatchGroup) {
                    self.privateDB.delete(withRecordID: record.recordID) { deletedRecordId, error in
                        guard error == nil else {
                            print("err: \(String(describing: error))");
                            self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                                self.deleteRecord(recordId: recordId)
                            })
                            return;
                        }
                    }
                }
            }
            
            dispatchGroup.notify(queue: DispatchQueue.main) {
                //워크스페이스 삭제
                let recordIdObject = CKRecord.ID(recordName: recordId)
                self.privateDB.delete(withRecordID: recordIdObject) { deletedRecordId, error in
                    guard error == nil else {
                        print("err: \(String(describing: error))");
                        self.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                            self.deleteRecord(recordId: recordId)
                        })
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
                                               options: [CKQuerySubscription.Options.firesOnRecordCreation, CKQuerySubscription.Options.firesOnRecordDeletion, CKQuerySubscription.Options.firesOnRecordUpdate])

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
        if (notification?.subscriptionID == "cloudkit-recordType-changes") {
            print("[CLOUD UPDATE] notification - \(String(describing: notification))")
            SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!) //일정 업데이트
        }
    }
    
    // MARK: - Review
    func showReviewTimer(second:Int) {
        DispatchQueue.main.async {
            if PremiumProducts.store.isProductPurchased(PremiumProducts.premiumVersion) {
                if !UserDefaults().bool(forKey: "sawReview") {
                    self.reviewTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(second), repeats: true, block: { timer in
                        self.reviewTimer?.invalidate()
                        self.reviewTimer = nil
                        DispatchQueue.main.async {
                            SKStoreReviewController.requestReview()   //리뷰 평점 작성 메서드4
                            UserDefaults().set(true, forKey: "sawReview")
                        }
                    })
                }
            } else {
                self.reviewTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(second), repeats: true, block: { timer in
                    if !PremiumProducts.store.isProductPurchased(PremiumProducts.premiumVersion) {
                        self.showPhurcaseDialog()
                    }
                })
            }
        }
    }
    
    func showPhurcaseDialog() {
        if IAPHelper.canMakePayments() {
            NotificationCenter.default.post(name: .showProgress, object: nil)
            
            PremiumProducts.store.requestProducts { (success, products) in
                NotificationCenter.default.post(name: .closeProgress, object: nil)
                if success, let product = products?.first {
                    let numberFormatter = NumberFormatter()
                    let locale = product.priceLocale
                    numberFormatter.numberStyle = .currency
                    numberFormatter.locale = locale
                    
                    self.openTwoBtnDialogOKCancel(message: product.localizedTitle, informativeText: product.localizedDescription, icon: #imageLiteral(resourceName: "Premium"),  leftBtnTitle: "Later...", rightBtnTitle: numberFormatter.string(from: product.price)!, { (response) in
                        if response == NSApplication.ModalResponse.alertSecondButtonReturn {
                            PremiumProducts.store.buyProduct(product)
                        }
                    })
                } else {
                    print("showPhurcaseDialog 실패!!!")
                }
            }
        } else {
            self.openOneBtnDialogOK(question: "Info", text: "Payment unavailable.") {
                print("Payment unavailable.")
            }
        }
    }
    
    @objc func buyComplete() {
        self.reviewTimer?.invalidate()
        self.reviewTimer = nil
        self.openOneBtnDialogOK(question: "Info", text: "Purchase completed!") {
            print("Purchase completed!")
            
            if ((self.popover.contentViewController as? PopOverViewController) == nil) {
                self.popover.contentViewController = SharedData.instance.popOverVC
                SharedData.instance.popOverVC.pinBtn.image = #imageLiteral(resourceName: "pin_white")
//                self.eventMonitor?.start()
            }
        }
    }
    
    func manageLauncherApp() {
        if UserDefaults().bool(forKey: "LaunchAtLogin") {
            let launcherAppId = "com.oq.MyWorkingListForMac.LauncherApplication"
            let runningApps = NSWorkspace.shared.runningApplications
            let isRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty
            
            SMLoginItemSetEnabled(launcherAppId as CFString, true)
            
            if isRunning {
                DistributedNotificationCenter.default().post(name: .killLauncher,
                                                             object: Bundle.main.bundleIdentifier!)
            }
        }
    }
    
    func enableLauncherApp(launcherAppId:String) {
        UserDefaults().set(true, forKey: "LaunchAtLogin")
        SMLoginItemSetEnabled(launcherAppId as CFString, true)
    }
    
    func disableLauncherApp(launcherAppId:String) {
        UserDefaults().set(false, forKey: "LaunchAtLogin")
        SMLoginItemSetEnabled(launcherAppId as CFString, false)
    }
    
    @objc func calendarDayDidChange(notification : NSNotification) {
        guard let seletedWorkSpace = SharedData.instance.seletedWorkSpace else {
            print("seletedWorkSpace is nil")
            return
        }
        SharedData.instance.workSpaceUpdateObserver?.onNext(seletedWorkSpace)
    }
}
