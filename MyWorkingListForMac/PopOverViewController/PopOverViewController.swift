//
//  PopOverViewController.swift
//  MyWorkingListForMac
//
//  Created by OQ on 26/09/2018.
//  Copyright © 2018 OQ. All rights reserved.
//

import Cocoa
import ApplicationServices
import RxSwift
import RxCocoa

public protocol PopOverViewControllerDelegate {
    /**
     하나의 셀 업데이트
     */
    func reloadTableWithUpdateCell(index:Int, title:String, body:String) -> Void;
    
    /**
     모든 셀 업데이트
     */
    func reloadTableAll() -> Void;
    
    /**
     리프레시 타임 라벨 업데이트
     */
    func setRefreshTimeLabel(text:String) -> Void;
}

class PopOverViewController: NSViewController, PopOverViewControllerDelegate {
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet var textView: NSTextView!
    @IBOutlet weak var textScrollView: NSScrollView!
    @IBOutlet weak public var taskScrollViewHeight: NSLayoutConstraint!
    @IBOutlet weak var editViewHeight: NSLayoutConstraint!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var extendBtn: NSButton!
    @IBOutlet weak var refreshTimeLabel: NSTextField!
    @IBOutlet weak var datePicker: NSDatePicker!
    @IBOutlet weak var dateUpdateBtn: NSButton!
    
    @IBOutlet weak var indicatorView: IndicatorView!
    /**
     편집창의 크기가 커져있는지 아닌지
     */
    var isExtendEditView = false
    
    /**
     선택된 row의 순번
     */
    var selectedRow = 1
    
    /**
     테이블의 모든 셀의 데이터를 담는다.(사용자가 기입하지 않은 날의 데이터도 들어있음)
     */
    var taskData: Array<myTask> = []
    
//    lazy var refreshControl: NSRefreshControl = {
//        let refreshControl = UIRefreshControl();
//        refreshControl.attributedTitle = NSAttributedString(string: "Load data a month ago");
//        refreshControl.addTarget(self, action: #selector(refreshWeatherData(_:)), for: .valueChanged)
//
//        return refreshControl
//    }()
    
    let disposeBag = DisposeBag()
    
    let EDIT_VIEW_HEIGHT = 100
    let TIMER_CHECK_REFRESH_INTERVAL: RxTimeInterval = 100 //100초마다 체크
    
    // MARK: ==============================
    // MARK: PopOverViewControllerDelegate
    func reloadTableWithUpdateCell(index:Int, title:String, body:String) {
        //해당 셀 데이터 업데이트
        self.taskData[index].title = title;
        self.taskData[index].body = body;

        DispatchQueue.main.async {
            let indexSet = IndexSet.init(integer: index)
            self.tableView.beginUpdates()
            self.tableView.removeRows(at: indexSet, withAnimation: .effectFade)
            self.tableView.insertRows(at: indexSet, withAnimation: .effectFade)
            self.tableView.endUpdates()
        }
    }
    
    func reloadTableAll() {
        let dayKeyFormatter = DateFormatter();
        dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyMMdd");
        
        for (index, element) in self.taskData.enumerated() {
            //*********dayKey 생성***********
            let dayKey:String = dayKeyFormatter.string(from: element.date);
            //******************************
            let dayTask:myTask! = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask;
            
            if (dayTask != nil) {
                self.taskData[index] = myTask.init(dayTask.id, self.taskData[index].date, dayTask.body, dayTask.title);
            }
        }
        
        DispatchQueue.main.async {
            self.tableView.reloadData();
        }
    }
    
    func setRefreshTimeLabel(text:String) {
        DispatchQueue.main.async {
            self.refreshTimeLabel.stringValue = text
        }
    }
    
    // MARK: ==============================
    // MARK: viewDidLoad
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) != nil,
            let screenSizeVal:popOverScreenSize = popOverScreenSize(rawValue: UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) as! Int) {
            self.taskScrollViewHeight.constant = screenSizeVal.getSize()
        } else {
            self.taskScrollViewHeight.constant = popOverScreenSize.medium.getSize()
            UserDefaults.standard.set(popOverScreenSize.medium.rawValue, forKey: SettingViewController.POPOVER_SCREEN_SIZE)
        }
        
        //noti for NSPopoverWillShowNotification
        NotificationCenter.default.addObserver(self, selector: #selector(popoverWillShow), name: NSPopover.willShowNotification, object: nil)
        
        //noti for show and close progress
        NotificationCenter.default.addObserver(self, selector: #selector(showProgress), name: .showProgress, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(closeProgress), name: .closeProgress, object: nil)
        
        //datePicker 이밴트 맵핑
        self.datePicker.target = self
        self.datePicker.action = #selector(datePickerChangeHandler)
        let action = NSEvent.EventTypeMask.mouseExited
        self.datePicker.sendAction(on: action)
        
        //데이터 초기화 옵져버
        Observable<myWorkspace>.create{ observer in
            SharedData.instance.workSpaceUpdateObserver = observer
            return Disposables.create()
            }.observeOn(MainScheduler.instance)
            .subscribe{
                print("[PopOverVC] load task in cloud data")
                self.titleLabel.stringValue = $0.element!.name
                self.taskData.removeAll()
                SharedData.instance.taskAllDic.removeAllObjects()
                
                //날짜 그리기
                if  (($0.element?.pivotDate) != nil) {
                    self.initTaskData(pivotDate: $0.element?.pivotDate)
                } else {
                    self.initTaskData(pivotDate: Date())
                }
                
                //클라우드에서 일일데이터를 가져오고 테이블 리로드
                (NSApplication.shared.delegate as! AppDelegate).getDayTask(startDate: (self.taskData.first?.date)!, endDate: (self.taskData.last?.date)!, workSpaceId: (SharedData.instance.seletedWorkSpace?.id)!)
                self.dateUpdateBtn.isHidden = true
                
            }.disposed(by: self.disposeBag)
        
        SharedData.instance.popViewContrllerDelegate = self
        
        //테스크 그리기
        SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
        
        self.setDidChangeTextViewNoti()
        self.setSyncTimeUpdateNoti()
    }
    
    @IBAction func pressSettingBtn(_ sender: Any) {
        //present setting View
        let settingVC = SettingViewController.init(nibName: "SettingViewController", bundle: Bundle.main)
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.popover.contentViewController = settingVC
    }
    
    @IBAction func pressRefreshBtn(_ sender: Any) {
        print("Refresh!")
        SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
    }
    
    @IBAction func pressBookMarkBtn(_ sender: Any) {
        print("BookMark!")
        let workspaceVC = WorkspaceViewController.init(nibName: "WorkspaceViewController", bundle: Bundle.main)
        let appDelegate = NSApplication.shared.delegate as! AppDelegate
        appDelegate.popover.contentViewController = workspaceVC
    }
    
    @IBAction func pressExtendBtn(_ sender: Any?) {
        let size:CGFloat = (popOverScreenSize(rawValue: UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) as! Int)?.getSize())!
        
        if isExtendEditView {
            self.isExtendEditView = false
            
            NSAnimationContext.runAnimationGroup({ (context) in
                context.duration = 0.2
                self.taskScrollViewHeight.animator().constant = size
                self.editViewHeight.animator().constant = CGFloat(self.EDIT_VIEW_HEIGHT)
            }) {
                self.extendBtn.image = NSImage.init(named: NSImage.enterFullScreenTemplateName)
            }
            
        } else {
            self.isExtendEditView = true
            
            NSAnimationContext.runAnimationGroup({ (context) in
                context.duration = 0.2
                self.taskScrollViewHeight.animator().constant = CGFloat(self.EDIT_VIEW_HEIGHT)
                self.editViewHeight.animator().constant = size
            }) {
                self.extendBtn.image = NSImage.init(named: NSImage.exitFullScreenTemplateName)
                self.tableView.scrollRowToVisible(self.selectedRow)
            }
        }
    }
    
    @IBAction func pressDateUpdateBtn(_ sender: Any) {
        let pivotDate = self.datePicker.dateValue
        SharedData.instance.seletedWorkSpace?.pivotDate = pivotDate
        SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
    }
    
    
    @objc func popoverWillShow() -> Void {
        self.textScrollView.flashScrollers()
        self.textView.window?.makeFirstResponder(self.textView.superview)
    }
    
    @objc func datePickerChangeHandler() -> Void {
        
        let pivotDate = self.datePicker.dateValue
        
        //same date check
        let dateFormatter = DateFormatter()
        dateFormatter.setLocalizedDateFormatFromTemplate("MM/yyyy")
        let taskDateForTodayCheck:String = dateFormatter.string(from: pivotDate)
        let todayDateForTodayCheck:String = dateFormatter.string(from: SharedData.instance.seletedWorkSpace!.pivotDate!)
        
        if taskDateForTodayCheck == todayDateForTodayCheck {  //년월이 같다면
            self.dateUpdateBtn.isHidden = true
        } else {
            self.dateUpdateBtn.isHidden = false
        }
    }
    
    @objc func showProgress() -> Void {
        print("[PopOverVC] showProgress")
        self.indicatorView.start()
    }
    
    @objc func closeProgress() -> Void {
        print("[PopOverVC] closeProgress")
        self.indicatorView.stop()
    }
    
    /**
     테이블 뷰 데이터 초기화
     */
    func initTaskData(pivotDate:Date!) -> Void {
        self.datePicker.dateValue = pivotDate
        
        //달에 몇일이나 있는지 가져오는 로직
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: pivotDate)!
        
        //해당 달의 시작일을 구하는 로직
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendar.startOfDay(for: pivotDate)))!
        
        let dayKeyFormatter = DateFormatter();
        dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyMMdd");
        
        //과거로부터 현재 미래까지
        for i in 0..<days.count {
            let date:Date = (Calendar.current.date(byAdding: .day, value: i, to: startOfMonth))!;
            
            //*********dayKey 생성***********
            let dayKey:String = dayKeyFormatter.string(from: date);
            //******************************
            let dayTask:myTask? = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask;
            
            if (dayTask != nil) {
                self.taskData.append(myTask(dayTask!.id, date, dayTask!.body, dayTask!.title));
            } else {
                self.taskData.append(myTask("", date, "", nil));
            }
        }
    }
}

// MARK: TableView
extension PopOverViewController: NSTableViewDataSource, NSTableViewDelegate {
    
    fileprivate enum CellIdentifiers {
        static let TaskCell = "TaskCellID"
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.taskData.count
    }
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        let task = self.taskData[row]
        if (task.body != nil) && (task.body != "") {    // 본문이 있을 경우
            return 100
        } else {
            return 22
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        print("seleted row: \(row)")
        self.selectedRow = row
        let task = self.taskData[self.selectedRow]
        
        self.textView.string = task.body
//        self.pressExtendBtn(nil)
        
        return true
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        //테스크 생성
        let task = self.taskData[row]

        var dateText: String = ""
        let cellIdentifier = CellIdentifiers.TaskCell
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: self) as? CustomCellView {
            
            let dateFormatter = DateFormatter()
            dateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
            let dayOfWeek:String = dateFormatter.string(from: task.date)
            dateFormatter.setLocalizedDateFormatFromTemplate("dd")
            let taskDate:String = dateFormatter.string(from: task.date)
            
            //today check
            dateFormatter.setLocalizedDateFormatFromTemplate("MM/dd/yyyy")
            let taskDateForTodayCheck:String = dateFormatter.string(from: task.date)
            let todayDateForTodayCheck:String = dateFormatter.string(from: Date())
            
            if taskDateForTodayCheck == todayDateForTodayCheck {  //오늘이라면
                dateText = "\(taskDate) [\(dayOfWeek)] - today!"
                cell.titleLabel?.backgroundColor = NSColor.init(red: 255/255, green: 224/255, blue: 178/255, alpha: 1)
            } else {
                let weekDay = Calendar.current.component(Calendar.Component.weekday, from: task.date)
                if weekDay == 1 {   //일요일이라면
                    cell.titleLabel?.backgroundColor = NSColor.init(red: 252/255, green: 228/255, blue: 236/255, alpha: 1)
                } else {
                    cell.titleLabel?.backgroundColor = NSColor.init(red: 227/255, green: 242/255, blue: 253/255, alpha: 1)
                }
                
                dateText = "\(taskDate) [\(dayOfWeek)]";
            }
            
            cell.titleLabel?.stringValue = dateText
            
            if (task.title != nil && task.title!.count > 0) {
                cell.titleLabel?.stringValue.append(" \(task.title!)")
            }
            
            cell.textField?.stringValue = task.body
            
            return cell
        }
        
        return nil
    }
}

// MARK: ==============================
// MARK: CustomCellView
class CustomCellView: NSTableCellView {
    
    @IBOutlet open var titleLabel: NSTextField?
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Drawing code here.
    }
    
}

// MARK: ==============================
// MARK: Noti 관련
extension PopOverViewController {
    func setDidChangeTextViewNoti() {
        NotificationCenter.default.rx
            .notification(NSText.didChangeNotification, object: self.textView)
            .debounce(1, scheduler: MainScheduler.instance)
            .subscribe({ notification in
                let task = self.taskData[self.selectedRow]
                task.body = self.textView.string
                
                let indexSet = IndexSet.init(integer: self.selectedRow)
                
                self.tableView.beginUpdates()
                self.tableView.removeRows(at: indexSet, withAnimation: .effectFade)
                self.tableView.insertRows(at: indexSet, withAnimation: .effectFade)
                self.tableView.endUpdates()
                
            }).disposed(by: self.disposeBag)
    }
    
    func setSyncTimeUpdateNoti() {
        let timer = Observable<Int>.interval(TIMER_CHECK_REFRESH_INTERVAL, scheduler: MainScheduler.instance)    // 0.5초마다 발행
        timer.subscribe { (time) in
            let syncTime:Double = UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) as! Double
            let timeInterval = Date().timeIntervalSince1970 - syncTime
            self.setRefreshTimeLabel(text: MyWorkingListUtil.transformTimeToString(time: Int(timeInterval)))
        }.disposed(by: self.disposeBag)
    }
}


