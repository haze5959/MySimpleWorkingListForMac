//
//  WorkspaceViewController.swift
//  MyWorkingListForMac
//
//  Created by OQ on 03/02/2019.
//  Copyright © 2019 OQ. All rights reserved.
//

import Cocoa
import CloudKit

class WorkspaceViewController: NSViewController {
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var indicatorView: IndicatorView!
    @IBOutlet weak var removeBtn: NSButton!
    @IBOutlet weak var editBtn: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
//        appDelegate.eventMonitor?.stop()
        //noti for show and close progress
        NotificationCenter.default.addObserver(self, selector: #selector(showProgress), name: .showProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeProgress), name: .closeProgress, object: nil)
        
        //워크스페이스를 선택해야지 enable 되도록
        self.removeBtn.isEnabled = false
        self.editBtn.isEnabled = false

        //아이템 더블 클릭 시 이벤트
        self.tableView.doubleAction = #selector(tableRowDoubleClickAction)
        
        self.initWorkSpace()
    }
    
    @IBAction func pressBackBtn(_ sender: Any) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        let sharedData = SharedData.instance
        appDelegate.popover.contentViewController = sharedData.popOverVC
        SharedData.instance.popOverVC.pinBtn.image = #imageLiteral(resourceName: "pin_white")
//        appDelegate.eventMonitor?.start()
        sharedData.workSpaceUpdateObserver?.onNext(sharedData.seletedWorkSpace!)
    }
    
    @IBAction func addWorkspaceBtn(_ sender: Any) {
        let msgWithDateType = NSAlert()
        msgWithDateType.addButton(withTitle: "Daily")      // 1st button
        msgWithDateType.addButton(withTitle: "Weekly")  // 2nd button
        msgWithDateType.addButton(withTitle: "Monthly")  // 3th button
        msgWithDateType.addButton(withTitle: "Cancel")  // 4th button
        msgWithDateType.messageText = "Please select a date type."
        
        var dateType = DateType.day
        
        let responseWithDateType = msgWithDateType.runModal()
        if responseWithDateType == NSApplication.ModalResponse.alertFirstButtonReturn { //Daily
            dateType = .day
        } else if responseWithDateType == NSApplication.ModalResponse.alertSecondButtonReturn { //Weekly
            dateType = .week
        } else if responseWithDateType == NSApplication.ModalResponse.alertThirdButtonReturn { //Monthly
            dateType = .month
        } else {
            return
        }
        
        let msgWithInputName = NSAlert()
        msgWithInputName.addButton(withTitle: "OK")      // 1st button
        msgWithInputName.addButton(withTitle: "Cancel")  // 2nd button
        msgWithInputName.messageText = "New WorkSpace"
        
        let txt = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        txt.placeholderString = "input your new workspace name..."
        txt.stringValue = ""
        
        msgWithInputName.accessoryView = txt
        let response = msgWithInputName.runModal()
        
        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
            if txt.stringValue != ""  {
                //******클라우드에 새 워크스페이즈 저장******
                let appDelegate = NSApplication.shared.delegate as! AppDelegate
                appDelegate.popover.contentViewController = SharedData.instance.popOverVC
                appDelegate.makeWorkSpace(workSpaceName: txt.stringValue, dateType: dateType)
                //***********************************
            } else {
                let alert = NSAlert()
                alert.messageText = "value is empty."
                alert.runModal()
            }
        }
    }
    
    @IBAction func removeWorkspaceBtn(_ sender: Any) {
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        let sharedData = SharedData.instance
        
        guard self.tableView.selectedRow >= 0 else {
            let alert = NSAlert()
            alert.messageText = "There is no selected workspace."
            alert.runModal()
            
            return;
        }
        
        //선택된 워크스페이스랑 똑같은 워크스페이스를 선택했다면
        guard sharedData.workSpaceArr[self.tableView.selectedRow].name != sharedData.seletedWorkSpace?.name else {
            let alert = NSAlert()
            alert.messageText = "This is seleted workspace."
            alert.runModal()
            
            return;
        }
        
        //워크스페이스가 2개 미만이라면
        guard sharedData.workSpaceArr.count > 1 else {
            let alert = NSAlert()
            alert.messageText = "At least you must have two workspace."
            alert.runModal()
            
            return;
        }

        //******클라우드 해당 워크스페이스 및 일정들 삭제******
        appDelegate.deleteRecord(recordId: SharedData.instance.workSpaceArr[self.tableView.selectedRow].id)
        //***********************************
        
        SharedData.instance.workSpaceArr.remove(at: self.tableView.selectedRow)
        self.tableView.reloadData();
    }
    
    @IBAction func editWorkspaceBtn(_ sender: Any) {
        
        guard self.tableView.selectedRow >= 0 else {
            let alert = NSAlert()
            alert.messageText = "There is no selected workspace."
            alert.runModal()
            
            return;
        }
        
        let msg = NSAlert()
        msg.addButton(withTitle: "OK")      // 1st button
        msg.addButton(withTitle: "Cancel")  // 2nd button
        msg.messageText = "Rename WorkSpace"
        
        let txt = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        txt.placeholderString = "Input your new workspace name..."
        txt.stringValue = SharedData.instance.workSpaceArr[self.tableView.selectedRow].name
        
        msg.accessoryView = txt
        let response = msg.runModal()
        
        if response == NSApplication.ModalResponse.alertFirstButtonReturn {
            if txt.stringValue != ""  {
                let appDelegate = NSApplication.shared.delegate as! AppDelegate
                let sharedData = SharedData.instance
                //******클라우드에 새 워크스페이즈 저장******
                appDelegate.updateWorkSpace(recordId: sharedData.workSpaceArr[self.tableView.selectedRow].id, newName: txt.stringValue)
                //***********************************
                sharedData.workSpaceArr[self.tableView.selectedRow] = myWorkspace(id: sharedData.workSpaceArr[self.tableView.selectedRow].id, name: txt.stringValue, dateType: sharedData.workSpaceArr[self.tableView.selectedRow].dateType, pivotDate: Date())
                
                //선택된 워크스페이스랑 똑같은 워크스페이스를 선택했다면
                if sharedData.workSpaceArr[self.tableView.selectedRow].id == sharedData.seletedWorkSpace?.id {
                    sharedData.seletedWorkSpace = sharedData.workSpaceArr[self.tableView.selectedRow]
                    UserDefaults().set(SharedData.instance.seletedWorkSpace?.id, forKey: "seletedWorkSpaceId");
                    UserDefaults().set(SharedData.instance.seletedWorkSpace?.name, forKey: "seletedWorkSpaceName");
                }
                
                self.tableView.reloadData();
                
            } else {
                let alert = NSAlert()
                alert.messageText = "Value is empty."
                alert.runModal()
            }
        }
    }
    
    func initWorkSpace() {
        NotificationCenter.default.post(name: .showProgress, object: nil)
        
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "workSpace", predicate: predicate)
        
        appDelegate.privateDB.perform(query, inZoneWith: nil) { records, error in
            guard error == nil else {
                print("err: \(String(describing: error))");
                appDelegate.openOneBtnDialogOK(question: (error?.localizedDescription)!, text: "Reload network connection.", {
                    self.initWorkSpace()
                })
                return;
            }
            
            let sharedData = SharedData.instance
            sharedData.workSpaceArr = []   //초기화
            
            for record in records!{
                let workSpaceName:String = record.value(forKey: "name") as! String
                let workSpaceDateType = record.value(forKey: "dateType") as! Int
                sharedData.workSpaceArr.append(myWorkspace.init(id:record.recordID.recordName, name:workSpaceName, dateType: DateType(rawValue: workSpaceDateType)!, pivotDate: Date()))
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .closeProgress, object: nil)
                self.tableView.reloadData()
            }
        }

    }
    
    @objc func tableRowDoubleClickAction() -> Void {
        print("[WorkspaceViewController] tableRowDoubleClickAction: \(self.tableView.selectedRow)")
        //기존이랑 똑같은 워크스페이스를 선택하지 않았다면
        if(SharedData.instance.workSpaceArr[self.tableView.selectedRow].name != SharedData.instance.seletedWorkSpace?.name){
            let sharedData = SharedData.instance
            let appDelegate = NSApplication.shared.delegate as! AppDelegate
            appDelegate.popover.contentViewController = SharedData.instance.popOverVC
            sharedData.seletedWorkSpace = SharedData.instance.workSpaceArr[self.tableView.selectedRow]
            sharedData.workSpaceUpdateObserver?.onNext(sharedData.workSpaceArr[self.tableView.selectedRow])
            UserDefaults().set(SharedData.instance.seletedWorkSpace?.id, forKey: "seletedWorkSpaceId");
            UserDefaults().set(SharedData.instance.seletedWorkSpace?.name, forKey: "seletedWorkSpaceName");
            SharedData.instance.popOverVC.editTextInit()
        }
    }
    
    @objc func showProgress() -> Void {
        print("[WorkspaceViewController] showProgress")
        self.indicatorView.start()
    }
    
    @objc func closeProgress() -> Void {
        print("[WorkspaceViewController] closeProgress")
        self.indicatorView.stop()
    }
    
}

extension WorkspaceViewController: NSTableViewDataSource, NSTableViewDelegate {

    fileprivate enum CellIdentifiers {
        static let TaskCell = "WorkSpaceCellID"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        let sharedData = SharedData.instance
        print("table row count: \(sharedData.workSpaceArr.count)")
        return sharedData.workSpaceArr.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        print("heightOfRow row: \(row)")
        return 22
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        print("seleted row: \(row)")
        self.removeBtn.isEnabled = true
        self.editBtn.isEnabled = true
        
        return true
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {

        //워크스페이스 patch
        let sharedData = SharedData.instance
        let workSpace = sharedData.workSpaceArr[row]

        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: CellIdentifiers.TaskCell), owner: self) as? NSTableCellView {
            
            var dateType = ""
            switch SharedData.instance.workSpaceArr[row].dateType! {
            case .day:
                dateType = "Daily"
            case .week:
                dateType = "Weekly"
            case .month:
                dateType = "Monthly"
            }
            
            if(SharedData.instance.workSpaceArr[row].name == SharedData.instance.seletedWorkSpace?.name){
                cell.textField?.stringValue = workSpace.name + " [\(dateType)]" + " - Seleted!";
            } else {
                cell.textField?.stringValue = workSpace.name + " [\(dateType)]"
            }

            return cell
        }

        return nil
    }
}
