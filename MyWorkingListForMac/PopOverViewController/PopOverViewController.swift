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
    func reloadTableWithUpdateCell(index:Int, body:String) -> Void;
    
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
    @IBOutlet weak var editedDateLabel: NSTextField!
    @IBOutlet weak var textScrollView: NSScrollView!
    @IBOutlet weak public var taskScrollViewHeight: NSLayoutConstraint!
    @IBOutlet weak var editViewHeight: NSLayoutConstraint!
    @IBOutlet weak var tableView: NSTableView!
    @IBOutlet weak var autoUpdateBtn: NSButton!
    @IBOutlet weak var extendBtn: NSButton!
    @IBOutlet weak var refreshTimeLabel: NSTextField!
    @IBOutlet weak var datePicker: NSDatePicker!
    @IBOutlet weak var dateUpdateBtn: NSButton!
    @IBOutlet weak var pinBtn: NSButton!
    
    @IBOutlet weak var indicatorView: IndicatorView!
    /**
     수정된 부분이 저장이 되었는지 아닌지
     */
    var shouldUpdate = false
    /**
     편집창의 크기가 커져있는지 아닌지
     */
    var isExtendEditView = false
    
    /**
     선택된 row의 순번
     */
    static let NOT_SELECTED = -1
    var CHANGE_UPDATE_TIME: RxTimeInterval = 5
    var selectedRow = NOT_SELECTED
    
    /**
     테이블의 모든 셀의 데이터를 담는다.(사용자가 기입하지 않은 날의 데이터도 들어있음)
     */
    var taskData: Array<myTask> = []
    
//    let autoUpdateTimer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(updateTimerHandler), userInfo: nil, repeats: true)
    var autoUpdateTimer: Disposable?
    
    let disposeBag = DisposeBag()
    
    let EDIT_VIEW_HEIGHT = 200
    let TASK_VIEW_HEIGHT = 140
    let TIMER_CHECK_REFRESH_INTERVAL: RxTimeInterval = 100 //100초마다 체크
    
    var isDarkMode = false
    
    // MARK: ==============================
    // MARK: PopOverViewControllerDelegate
    func reloadTableWithUpdateCell(index:Int, body:String) {
        if index != -1 {
            //해당 셀 데이터 업데이트
            let task = self.taskData[index]
            task.body = body;
            
            DispatchQueue.main.async {
                let indexSet = IndexSet.init(integer: index)
                self.tableView.beginUpdates()
                self.tableView.removeRows(at: indexSet, withAnimation: .effectFade)
                self.tableView.insertRows(at: indexSet, withAnimation: .effectFade)
                self.tableView.endUpdates()
            }
        }
    }
    
    func reloadTableAll() {
        for (index, element) in self.taskData.enumerated() {
            //*********dayKey 생성***********
            let dayKey:String = DateFormatter.localizedString(from: element.date, dateStyle: .short, timeStyle: .none)
            //******************************
            let dayTask:myTask! = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask;
            
            if (dayTask != nil) {
                self.taskData[index] = myTask.init(dayTask.index, dayTask.id, self.taskData[index].date, dayTask.body);
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
        
        if self.view.isDarkMode {
            self.isDarkMode = true
            self.extendBtn.image = #imageLiteral(resourceName: "expanding_arrow_white")
        } else {
            self.isDarkMode = false
            self.extendBtn.image = #imageLiteral(resourceName: "expanding_arrow")
        }
        
        self.textView.allowsUndo = true
        self.autoUpdateBtn.isHidden = true
        if UserDefaults.standard.integer(forKey: SettingViewController.AUTO_UPDATE_TIME) > 0 {
            self.CHANGE_UPDATE_TIME = RxTimeInterval(UserDefaults.standard.integer(forKey: SettingViewController.AUTO_UPDATE_TIME))
        }
        
        if UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) != nil,
            let screenSizeVal:popOverScreenSize = popOverScreenSize(rawValue: UserDefaults.standard.object(forKey: SettingViewController.POPOVER_SCREEN_SIZE) as! Int) {
            self.taskScrollViewHeight.constant = screenSizeVal.getSize()
        } else {
            self.taskScrollViewHeight.constant = popOverScreenSize.medium.getSize()
            UserDefaults.standard.set(popOverScreenSize.medium.rawValue, forKey: SettingViewController.POPOVER_SCREEN_SIZE)
        }
        
        self.tableView.doubleAction = #selector(doubleClickTableRow)
        
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
        
        //Pin 버튼 이벤트 등록
//        self.pinBtn.rx.tap.subscribe(onNext: { () in
//            guard let eventMonitor = (NSApplication.shared.delegate as! AppDelegate).eventMonitor else {
//                return
//            }
//
//            if eventMonitor.monitor == nil {
//                self.pinBtn.image = #imageLiteral(resourceName: "pin_white")
//                eventMonitor.start()
//            } else {
//                self.pinBtn.image = #imageLiteral(resourceName: "pin_black")
//                eventMonitor.stop()
//            }
//        }).disposed(by: self.disposeBag)
        
        //데이터 초기화 옵져버
        Observable<myWorkspace>.create{ observer in
            SharedData.instance.workSpaceUpdateObserver = observer
            return Disposables.create()
            }.observeOn(MainScheduler.instance)
            .subscribe{
                print("[PopOverVC] load task in cloud data")
                self.updateSelectedRow()
                self.titleLabel.stringValue = $0.element!.name
                self.taskData.removeAll()
                SharedData.instance.taskAllDic.removeAllObjects()
                
                guard let workSpace = $0.element else {
                    return
                }
                
                switch workSpace.dateType! {
                case .day:
                    if  ((workSpace.pivotDate) != nil) {
                        self.initTaskData(pivotDate: workSpace.pivotDate)
                    } else {
                        self.initTaskData(pivotDate: Date())
                    }
                case .week:
                    if  ((workSpace.pivotDate) != nil) {
                        self.initTaskDataForWeek(pivotDate: workSpace.pivotDate)
                    } else {
                        self.initTaskDataForWeek(pivotDate: Date())
                    }
                case .month:
                    if  ((workSpace.pivotDate) != nil) {
                        self.initTaskDataForMonth(pivotDate: workSpace.pivotDate)
                    } else {
                        self.initTaskDataForMonth(pivotDate: Date())
                    }
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
        self.updateSelectedRow()
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
                if self.isDarkMode {
                    self.extendBtn.image = #imageLiteral(resourceName: "expanding_arrow_white")
                } else {
                    self.extendBtn.image = #imageLiteral(resourceName: "expanding_arrow")
                }
            }
            
        } else {
            self.isExtendEditView = true
            
            NSAnimationContext.runAnimationGroup({ (context) in
                context.duration = 0.2
                self.taskScrollViewHeight.animator().constant = CGFloat(TASK_VIEW_HEIGHT)
                self.editViewHeight.animator().constant = size
            }) {
                if self.isDarkMode {
                    self.extendBtn.image = #imageLiteral(resourceName: "collapse_arrow_white")
                } else {
                    self.extendBtn.image = #imageLiteral(resourceName: "collapse_arrow")
                }
                self.tableView.scrollRowToVisible(self.selectedRow)
            }
        }
    }
    
    @IBAction func pressDateUpdateBtn(_ sender: Any) {
        self.updateSelectedRow()
        let pivotDate = self.datePicker.dateValue
        SharedData.instance.seletedWorkSpace?.pivotDate = pivotDate
        SharedData.instance.workSpaceUpdateObserver?.onNext(SharedData.instance.seletedWorkSpace!)
        
        self.editTextInit()
    }
    
    @IBAction func pressAutoUpdateBtn(_ sender: Any) {
        self.updateSelectedRow()
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
    
    //초기화 구문
    func editTextInit() {
        self.selectedRow = PopOverViewController.NOT_SELECTED
        self.editedDateLabel.stringValue = "Not seleted"
        self.textView.string = ""
    }
    
    func updateSelectedRow() {
        if self.shouldUpdate {
            self.autoUpdateBtn.isHidden = true
            self.autoUpdateTimer?.dispose()
            
            self.shouldUpdate = false
            let task = self.taskData[self.selectedRow]
            task.body = self.textView.string
            
            let indexSet = IndexSet.init(integer: self.selectedRow)
            
            self.tableView.beginUpdates()
            self.tableView.removeRows(at: indexSet, withAnimation: .effectFade)
            self.tableView.insertRows(at: indexSet, withAnimation: .effectFade)
            self.tableView.endUpdates()
            
            let appDelegate = NSApplication.shared.delegate as! AppDelegate
            appDelegate.updateWaitingTask.accept(task)
            self.autoUpdateBtn.isHidden = true
        }
    }
}

// MARK: 데이터 초기화
extension PopOverViewController {
    // MARK: Day init
    func initTaskData(pivotDate:Date!) -> Void {
        self.datePicker.dateValue = pivotDate
        
        //달에 몇일이나 있는지 가져오는 로직
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: pivotDate)!
        
        //해당 달의 시작일을 구하는 로직
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendar.startOfDay(for: pivotDate)))!
        
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyMMdd")
        
        //과거로부터 현재 미래까지
        for i in 0..<days.count {
            let date:Date = (Calendar.current.date(byAdding: .day, value: i, to: startOfMonth))!;
            
            //*********dayKey 생성***********
            let dayKey:String = dayKeyFormatter.string(from: date)
            //******************************
            let dayTask:myTask? = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask;
            
            if (dayTask != nil) {
                self.taskData.append(myTask(i, dayTask!.id, date, dayTask!.body));
            } else {
                self.taskData.append(myTask(i ,"", date, ""));
            }
        }
    }
    
    // MARK: Week init
    func initTaskDataForWeek(pivotDate:Date!) -> Void {
        self.datePicker.dateValue = pivotDate
        
        //달에 몇주나 있는지 가져오는 로직
        let calendar = Calendar.current
        let weeks = calendar.range(of: .weekOfMonth, in: .month, for: pivotDate)!
        
        //해당 주의 시작일을 구하는 로직
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: calendar.startOfDay(for: pivotDate)))!
        let weekPivot = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: startOfMonth))!   //일요일로 변경
        
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyMMdd")
        
        //과거로부터 현재 미래까지
        for i in 0..<weeks.count {
            let date:Date = (Calendar.current.date(byAdding: .weekOfMonth, value: i, to: weekPivot))!
            
            //*********dayKey 생성***********
            let dayKey:String = dayKeyFormatter.string(from: date)
            //******************************
            let dayTask:myTask? = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask
            
            if (dayTask != nil) {
                self.taskData.append(myTask(i, dayTask!.id, date, dayTask!.body))
            } else {
                self.taskData.append(myTask(i ,"", date, ""))
            }
        }
    }
    
    // MARK: Month init
    func initTaskDataForMonth(pivotDate:Date!) -> Void {
        let monthPivot = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: pivotDate))!   //해당 달의 첫째날로 변경
        self.datePicker.dateValue = monthPivot
        
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyMMdd")
        
        //과거로부터 현재 미래까지
        for i in 0..<12 {
            let date:Date = (Calendar.current.date(byAdding: .month, value: i, to: monthPivot))!;
            
            //*********dayKey 생성***********
            let dayKey:String = dayKeyFormatter.string(from: date)
            //******************************
            let dayTask:myTask? = SharedData.instance.taskAllDic.object(forKey: dayKey) as? myTask;
            
            if (dayTask != nil) {
                self.taskData.append(myTask(i, dayTask!.id, date, dayTask!.body));
            } else {
                self.taskData.append(myTask(i ,"", date, ""));
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
        
        switch SharedData.instance.seletedWorkSpace!.dateType! {
        case .day:
            if (task.body != nil) && (task.body != "") {    // 본문이 있을 경우
                return CGFloat(TASK_VIEW_HEIGHT)
            } else {
                return 22
            }
        case .week:
            return CGFloat(TASK_VIEW_HEIGHT)
        case .month:
            return CGFloat(TASK_VIEW_HEIGHT)
        }
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        print("seleted row: \(row)")
        self.updateSelectedRow()
        self.selectedRow = row
        let task = self.taskData[self.selectedRow]
        
        
        DispatchQueue.main.async {
            let dayKeyFormatter = DateFormatter()
            
            switch SharedData.instance.seletedWorkSpace!.dateType! {
            case .day:
                dayKeyFormatter.setLocalizedDateFormatFromTemplate("EEEE")
                let dateEEE:String = dayKeyFormatter.string(from: task.date)
                let editedDateStr:String = DateFormatter.localizedString(from: task.date, dateStyle: .short, timeStyle: .none)
                self.editedDateLabel.stringValue = "\(editedDateStr) \(dateEEE)"
                
            case .week:
                let weekNumber = Calendar.current.component(.weekOfMonth, from: task.date)  //첫 주는 1부터 시작
                dayKeyFormatter.setLocalizedDateFormatFromTemplate("MM/dd")
                let sunday = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: task.date))!
                let sundayStr:String = dayKeyFormatter.string(from: sunday)
                let saturday = Calendar.current.date(byAdding: .day, value: 6, to: sunday)
                let saturdayStr:String = dayKeyFormatter.string(from: saturday!)
            
                self.editedDateLabel.stringValue = "\(weekNumber) Week(\(sundayStr)~\(saturdayStr))"
            case .month:
                dayKeyFormatter.setLocalizedDateFormatFromTemplate("yyyy/MM")
                self.editedDateLabel.stringValue = dayKeyFormatter.string(from: task.date)
            }
            
            self.textView.string = task.body
        }
        
        return true
    }
    
    @objc func doubleClickTableRow() {
        print("double Click row!")
        self.pressExtendBtn(nil)
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        
        //테스크 생성
        let task = self.taskData[row]

        var dateText: String = ""
        let cellIdentifier = CellIdentifiers.TaskCell
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: cellIdentifier), owner: self) as? CustomCellView {
            
            let dateCompareFormatter = DateFormatter()
            dateCompareFormatter.setLocalizedDateFormatFromTemplate("MM/dd/yyyy")
            
            let dateFormatter = DateFormatter()
            switch SharedData.instance.seletedWorkSpace!.dateType! {
            case .day:
                dateFormatter.setLocalizedDateFormatFromTemplate("EEEE")
                let dayOfWeek:String = dateFormatter.string(from: task.date)
                dateFormatter.setLocalizedDateFormatFromTemplate("dd")
                let taskDate:String = dateFormatter.string(from: task.date)
                
                //today check
                let taskDateForTodayCheck:String = dateCompareFormatter.string(from: task.date)
                let todayDateForTodayCheck:String = dateCompareFormatter.string(from: Date())
                
                if taskDateForTodayCheck == todayDateForTodayCheck {  //오늘이라면
                    dateText = "\(taskDate) [\(dayOfWeek)] - today!"
                    cell.titleLabel?.backgroundColor = NSColor.init(red: 255/255, green: 224/255, blue: 178/255, alpha: 1)
                    tableView.scrollRowToVisible(row)   //금일이었을 경우 바로 해당 셀이 보일 수 있게
                    self.selectedRow = row
                    
                    DispatchQueue.main.async {
                        let editedDateStr:String = DateFormatter.localizedString(from: task.date, dateStyle: .short, timeStyle: .none)
                        self.editedDateLabel.stringValue = "\(editedDateStr) \(dayOfWeek)"
                        self.textView.string = task.body
                    }
                } else {
                    let weekDay = Calendar.current.component(Calendar.Component.weekday, from: task.date)
                    if weekDay == 1 {   //일요일이라면
                        cell.titleLabel?.backgroundColor = NSColor.init(red: 252/255, green: 228/255, blue: 236/255, alpha: 1)
                    } else {
                        cell.titleLabel?.backgroundColor = NSColor.init(red: 227/255, green: 242/255, blue: 253/255, alpha: 1)
                    }
                    
                    dateText = "\(taskDate) [\(dayOfWeek)]";
                }
            case .week:
                let taskDate:String = dateCompareFormatter.string(from: task.date)
                
                let weekNumber = Calendar.current.component(.weekOfMonth, from: task.date)  //첫 주는 1부터 시작
                dateFormatter.setLocalizedDateFormatFromTemplate("MM/dd")
                let sunday = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: task.date))!
                let sundayStr:String = dateFormatter.string(from: sunday)
                let saturday = Calendar.current.date(byAdding: .day, value: 6, to: sunday)
                let saturdayStr:String = dateFormatter.string(from: saturday!)
                
                let weekPivot = Calendar.current.date(from: Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date()))!   //일요일로 변경
                let todayDate:String = dateCompareFormatter.string(from: weekPivot)
                
                if taskDate == todayDate {  //오늘이라면
                    dateText = "\(weekNumber) Week(\(sundayStr)~\(saturdayStr)) - today!"
                    cell.titleLabel!.backgroundColor = NSColor.init(red: 255/255, green: 224/255, blue: 178/255, alpha: 1)
                } else {
                    dateText = "\(weekNumber) Week(\(sundayStr)~\(saturdayStr))"
                    cell.titleLabel!.backgroundColor = NSColor.init(red: 227/255, green: 242/255, blue: 253/255, alpha: 1)
                }
            case .month:
                let taskDate:String = dateCompareFormatter.string(from: task.date)
                
                dateFormatter.setLocalizedDateFormatFromTemplate("yyyy/MM")
                let monthStr:String = dateFormatter.string(from: task.date)
                
                let monthPivot = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!   //해당 달의 첫째날로 변경
                let todayDate:String = dateCompareFormatter.string(from: monthPivot)
                
                if taskDate == todayDate {  //오늘이라면
                    dateText = "\(monthStr) - today!"
                    cell.titleLabel!.backgroundColor = NSColor.init(red: 255/255, green: 224/255, blue: 178/255, alpha: 1)
                } else {
                    dateText = "\(monthStr)"
                    cell.titleLabel!.backgroundColor = NSColor.init(red: 227/255, green: 242/255, blue: 253/255, alpha: 1)
                }
            }
            
            cell.titleLabel?.stringValue = dateText
            
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
        //다른 셀 선택, 워크스페이스 변경 등으로 CHANGE_UPDATE_TIME을 기다릴 필요없이 바로 업데이트를 했을 경우를 판별하기 위한 변수 설정
        Observable.merge(
            NotificationCenter.default.rx.notification(NSText.didChangeNotification, object: self.textView)
            ).subscribe({ notification in
            if self.selectedRow != PopOverViewController.NOT_SELECTED {
                self.shouldUpdate = true
                self.autoUpdateTimer?.dispose()
                self.autoUpdateBtn.title = "Auto update: \(Int(self.CHANGE_UPDATE_TIME))s"
                self.autoUpdateBtn.isHidden = false
                self.tableView.scrollRowToVisible(self.selectedRow)
                
                self.autoUpdateTimer = Observable<Int>
                    .interval(1, scheduler: MainScheduler.instance)
                    .take(Int(self.CHANGE_UPDATE_TIME))        // CHANGE_UPDATE_TIME 만큼 발행
                    .map({ Int(self.CHANGE_UPDATE_TIME) - ($0 + 1) })
                    .subscribeOn(MainScheduler.instance)
                    .subscribe(onNext: { (seconds) in
                        if seconds < 0 {
                            self.updateSelectedRow()
                        } else {
                            self.autoUpdateBtn.title = "Auto update: \(seconds)s"
                        }
                        
                    }, onCompleted: {
                        self.updateSelectedRow()
                    })
            }
                
        }).disposed(by: self.disposeBag)
        
        //CHANGE_UPDATE_TIME 대기 후 업데이트
//        changeNotiObservable.debounce(PopOverViewController.CHANGE_UPDATE_TIME, scheduler: MainScheduler.instance)
//                            .subscribe({ notification in
//                                self.updateSelectedRow()
//
//                            }).disposed(by: self.disposeBag)
    }
    
    func setSyncTimeUpdateNoti() {
        let timer = Observable<Int>.interval(TIMER_CHECK_REFRESH_INTERVAL, scheduler: MainScheduler.instance)
        timer.subscribe { (time) in
            let syncTime:Double = UserDefaults.standard.object(forKey: AppDelegate.CLOUD_SYNC_TIME) as! Double
            let timeInterval = Date().timeIntervalSince1970 - syncTime
            self.setRefreshTimeLabel(text: MyWorkingListUtil.transformTimeToString(time: Int(timeInterval)))
        }.disposed(by: self.disposeBag)
    }
}


