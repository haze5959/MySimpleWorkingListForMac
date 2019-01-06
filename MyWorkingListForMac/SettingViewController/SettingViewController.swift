//
//  SettingViewController.swift
//  MyWorkingListForMac
//
//  Created by OQ on 29/09/2018.
//  Copyright © 2018 OQ. All rights reserved.
//

import Cocoa
import KeyHolder
import Magnet
import RxCocoa
import RxSwift

enum popOverScreenSize: Int {
    case small
    case medium
    case large
    
    func getSize() -> CGFloat {
        switch self {
        case .small:
            return 300
        case .medium:
            return 500
        case .large:
            return 700
        }
    }
}

class SettingViewController: NSViewController {
    let disposeBag = DisposeBag();
    static let HOTKEY_OPEN = "KeyHolderOpen"
    static let POPOVER_SCREEN_SIZE = "popOverScreenSize"
    @IBOutlet weak var syncTimeLabel: NSTextField!
    @IBOutlet weak var icloudOwnerLabel: NSTextField!
    
    @IBOutlet weak var recordView: RecordView!
    
    @IBOutlet weak var smallRadioBtn: NSButton!
    @IBOutlet weak var mediumRadioBtn: NSButton!
    @IBOutlet weak var largeRadioBtn: NSButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.eventMonitor?.stop()
        
        self.recordView.tintColor = NSColor(red: 0.164, green: 0.517, blue: 0.823, alpha: 1)
        
        appDelegate.container.requestApplicationPermission(.userDiscoverability) { (status, error) in
            appDelegate.container.fetchUserRecordID { (recordId, error) in
                guard error == nil else {
                    DispatchQueue.main.async {
                        self.icloudOwnerLabel.stringValue = "Unkwon";
                    }
                    return;
                }
                
                appDelegate.container.discoverUserIdentity(withUserRecordID: recordId!, completionHandler: { (userID, error) in
                    guard error == nil else {
                        DispatchQueue.main.async {
                            self.icloudOwnerLabel.stringValue = "Unkwon";
                        }
                        return;
                    }
                    
                    DispatchQueue.main.async {
                        self.icloudOwnerLabel.stringValue = "\((userID?.nameComponents?.givenName)! + " " + (userID?.nameComponents?.familyName)!)";
                    }
                })
            }
        }
        
        //setting radio Btn
        if UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) != nil,
            let screenSizeVal:popOverScreenSize = popOverScreenSize(rawValue: UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) as! Int) {
            switch screenSizeVal{
            case .small:
                self.smallRadioBtn.state = NSControl.StateValue.on
                self.mediumRadioBtn.state = NSControl.StateValue.off
                self.largeRadioBtn.state = NSControl.StateValue.off
            case .medium:
                self.smallRadioBtn.state = NSControl.StateValue.off
                self.mediumRadioBtn.state = NSControl.StateValue.on
                self.largeRadioBtn.state = NSControl.StateValue.off
            case .large:
                self.smallRadioBtn.state = NSControl.StateValue.off
                self.mediumRadioBtn.state = NSControl.StateValue.off
                self.largeRadioBtn.state = NSControl.StateValue.on
            }
        } else {
            UserDefaults.standard.set(popOverScreenSize.medium.rawValue, forKey: SettingViewController.POPOVER_SCREEN_SIZE)
            self.mediumRadioBtn.state = NSControl.StateValue.on
        }
        
        Observable.from([
            self.smallRadioBtn.rx.tap.map{popOverScreenSize.small},
            self.mediumRadioBtn.rx.tap.map{popOverScreenSize.medium},
            self.largeRadioBtn.rx.tap.map{popOverScreenSize.large}
            ]).merge()
            .bind { (popOverScreenSize) in
                print("change popOverScreenSize: \(popOverScreenSize)")
                SharedData.instance.popOverVC.taskScrollViewHeight.constant = popOverScreenSize.getSize()
                UserDefaults.standard.set(popOverScreenSize.rawValue, forKey: SettingViewController.POPOVER_SCREEN_SIZE)
        }.disposed(by: self.disposeBag)
        

        //get hotkey from userDefault
        if let hotKeyToOpenData = UserDefaults.standard.object(forKey: SettingViewController.HOTKEY_OPEN) as? Data {
            if let hotKeyToOpen = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToOpenData) {
                self.recordView.keyCombo = hotKeyToOpen
                self.recordView.delegate = self
            }
        }
        
        guard UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) != nil else {
            self.syncTimeLabel.stringValue = "Do not sync..."
            return;
        }
        
        let syncTime:Double = UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) as! Double
        let timeInterval = Date().timeIntervalSince1970 - syncTime
        self.syncTimeLabel.stringValue = self.transformTimeToString(time: Int(timeInterval))
    }

    @IBAction func pressCloseBtn(_ sender: Any) {
        //present work list View
//        let popOverVC = PopOverViewController.init(nibName: "PopOverViewController", bundle: Bundle.main)
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.popover.contentViewController = SharedData.instance.popOverVC
        appDelegate.eventMonitor?.start()
    }
}

// MARK: - RecordView Delegate
extension SettingViewController: RecordViewDelegate {
    func recordViewShouldBeginRecording(_ recordView: RecordView) -> Bool {
        return true
    }
    
    func recordView(_ recordView: RecordView, canRecordKeyCombo keyCombo: KeyCombo) -> Bool {
        // You can customize validation
        return true
    }
    
    func recordViewDidClearShortcut(_ recordView: RecordView) {
        print("clear shortcut")
        HotKeyCenter.shared.unregisterHotKey(with: SettingViewController.HOTKEY_OPEN)
    }
    
    func recordViewDidEndRecording(_ recordView: RecordView) {
        print("end recording")
    }
    
    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo) {
        HotKeyCenter.shared.unregisterHotKey(with: SettingViewController.HOTKEY_OPEN)
        let hotKey = HotKey(identifier: SettingViewController.HOTKEY_OPEN, keyCombo: keyCombo, target: NSApplication.shared.delegate as! AppDelegate, action: #selector(AppDelegate.hotkeyCalled))
        hotKey.register()
        
        if let encoded = try? JSONEncoder().encode(keyCombo) {
            UserDefaults.standard.set(encoded, forKey: SettingViewController.HOTKEY_OPEN)
        }
    }
    
// MARK: - Time to String
    func transformTimeToString(time: Int) -> String {
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
