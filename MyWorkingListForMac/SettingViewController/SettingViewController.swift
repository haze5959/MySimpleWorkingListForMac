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
import LaunchAtLogin

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

enum hotKeyEnum: String {
    case HOTKEY_OPEN = "KeyHolderOpen"
    case HOTKEY_REFRESH = "KeyHolderRefresh"
}

class SettingViewController: NSViewController {
    let disposeBag = DisposeBag();
    static let POPOVER_SCREEN_SIZE = "popOverScreenSize"
    static let AUTO_UPDATE_TIME = "autoUpdateTime"
    @IBOutlet weak var syncTimeLabel: NSTextField!
    @IBOutlet weak var icloudOwnerLabel: NSTextField!
    
    @IBOutlet weak var openPopoverRecordView: RecordView!
    @IBOutlet weak var refreshRecordView: RecordView!
    
    @IBOutlet weak var smallRadioBtn: NSButton!
    @IBOutlet weak var mediumRadioBtn: NSButton!
    @IBOutlet weak var largeRadioBtn: NSButton!
    @IBOutlet weak var autoUpdateTimeInterval: NSTextField!
    @IBOutlet weak var launchLoginAppCheckBox: NSButton!
    
    private let disposedBag: DisposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        print("LaunchAtLogin: \(LaunchAtLogin.isEnabled)")
        self.launchLoginAppCheckBox.state = UserDefaults().bool(forKey: "LaunchAtLogin") ? .on : .off
        
        self.launchLoginAppCheckBox.rx.tap.subscribe { (event) in
            if self.launchLoginAppCheckBox.state == .on {
                LaunchAtLogin.isEnabled = true
                UserDefaults().set(true, forKey: "LaunchAtLogin")
            } else {
                LaunchAtLogin.isEnabled = false
                UserDefaults().set(false, forKey: "LaunchAtLogin")
            }
            
            print("LaunchAtLogin: \(LaunchAtLogin.isEnabled)")
        }.disposed(by: self.disposeBag)
        
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.eventMonitor?.stop()
        
        self.openPopoverRecordView.tintColor = NSColor(red: 0.164, green: 0.517, blue: 0.823, alpha: 1)
        self.refreshRecordView.tintColor = NSColor(red: 0.164, green: 0.517, blue: 0.823, alpha: 1)
        
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
        
        self.openPopoverRecordView.delegate = self
        self.refreshRecordView.delegate = self
        
        //get hotkey from userDefault
        if let hotKeyToOpenData = UserDefaults.standard.object(forKey: hotKeyEnum.HOTKEY_OPEN.rawValue) as? Data {
            if let hotKeyToOpen = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToOpenData) {
                self.openPopoverRecordView.keyCombo = hotKeyToOpen
                
            }
        }
        
        if let hotKeyToRefreshData = UserDefaults.standard.object(forKey: hotKeyEnum.HOTKEY_REFRESH.rawValue) as? Data {
            if let hotKeyToRefresh = try? JSONDecoder().decode(KeyCombo.self, from: hotKeyToRefreshData) {
                self.refreshRecordView.keyCombo = hotKeyToRefresh
                
            }
        }
        
        guard UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) != nil else {
            self.syncTimeLabel.stringValue = "Do not sync..."
            return;
        }
        
        let syncTime:Double = UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) as! Double
        let timeInterval = Date().timeIntervalSince1970 - syncTime

        self.syncTimeLabel.stringValue = MyWorkingListUtil.transformTimeToString(time: Int(timeInterval))
        
        //update time interval init
        if UserDefaults.standard.integer(forKey: SettingViewController.AUTO_UPDATE_TIME) < 1 {
            UserDefaults().set(5, forKey: SettingViewController.AUTO_UPDATE_TIME);
        }
        self.autoUpdateTimeInterval.integerValue = UserDefaults.standard.integer(forKey: SettingViewController.AUTO_UPDATE_TIME)
        NotificationCenter.default.rx.notification(NSTextField.textDidChangeNotification, object: self.autoUpdateTimeInterval)
            .debounce(0.5, scheduler: MainScheduler.instance)
            .subscribe(onNext: { (notification) in
                if self.autoUpdateTimeInterval.stringValue.count > 0, self.autoUpdateTimeInterval.integerValue < 1 {
                    self.autoUpdateTimeInterval.integerValue = Int(SharedData.instance.popOverVC.CHANGE_UPDATE_TIME)
                    NSSound.beep()
                    return
                }
                
                UserDefaults().set(self.autoUpdateTimeInterval.integerValue, forKey: SettingViewController.AUTO_UPDATE_TIME);
                SharedData.instance.popOverVC.CHANGE_UPDATE_TIME = RxTimeInterval(self.autoUpdateTimeInterval.integerValue)
            }).disposed(by: self.disposeBag)
    }

    @IBAction func pressCloseBtn(_ sender: Any) {
        //present work list View
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.popover.contentViewController = SharedData.instance.popOverVC
        SharedData.instance.popOverVC.pinBtn.image = #imageLiteral(resourceName: "pin_white")
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
        print("clear shortcut \(recordView.identifier?.rawValue ?? "Unkown")")
        HotKeyCenter.shared.unregisterHotKey(with: recordView.identifier!.rawValue)
        UserDefaults.standard.removeObject(forKey: hotKeyEnum.HOTKEY_OPEN.rawValue)
    }
    
    func recordViewDidEndRecording(_ recordView: RecordView) {
        print("end recording")
    }
    
    func recordView(_ recordView: RecordView, didChangeKeyCombo keyCombo: KeyCombo) {
        print("edit recording")
        HotKeyCenter.shared.unregisterHotKey(with: recordView.identifier!.rawValue)
        let hotKeyVal =  hotKeyEnum.init(rawValue: recordView.identifier!.rawValue)!
        
        switch hotKeyVal {
        case .HOTKEY_OPEN:
            let hotKey = HotKey(identifier: hotKeyVal.rawValue, keyCombo: keyCombo, target: NSApplication.shared.delegate as! AppDelegate, action: #selector(AppDelegate.hotkeyOpenCalled))
            hotKey.register()
            
        case .HOTKEY_REFRESH:
            let hotKey = HotKey(identifier: hotKeyVal.rawValue, keyCombo: keyCombo, target: NSApplication.shared.delegate as! AppDelegate, action: #selector(AppDelegate.hotkeyRefreshCalled))
            hotKey.register()
        }
        
        if let encoded = try? JSONEncoder().encode(keyCombo) {
            UserDefaults.standard.set(encoded, forKey: recordView.identifier!.rawValue)
        }
    }

}
