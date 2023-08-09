import SwiftUI
import Combine
import shared

let bottomNavigationHeight = 56.0 // todo

private let dividerPadding = 8.0
private let dividerColor: UIColor = .systemGray4

private let menuIconSize = bottomNavigationHeight

private let taskCountsHeight = 36.0

private let taskItemHeight = 36.0
private let taskListContentPadding = 4.0

private let menuColor = MainVM.companion.menuColor.toColor()

private let navAndTasksTextHeight = bottomNavigationHeight + taskCountsHeight

struct MainView: View {

    @State private var vm = MainVM()
    @State private var isTimerActivitiesPresented = false

    @State private var isSettingsSheetPresented = false

    @EnvironmentObject private var timetoSheet: TimetoSheet

    @State private var isPurpleAnim = true

    static var lastInstance: MainView? = nil

    @State private var triggersChecklist: ChecklistModel?
    @State private var isTriggersChecklistPresented = false

    private let shortcutPublisher: AnyPublisher<ShortcutModel, Never> = UtilsKt.uiShortcutFlow.toPublisher()
    private let checklistPublisher: AnyPublisher<ChecklistModel, Never> = UtilsKt.uiChecklistFlow.toPublisher()

    var body: some View {

        VMView(vm: vm, stack: .ZStack(alignment: .bottom)) { state in

            /// # PROVOKE_STATE_UPDATE
            EmptyView().id("MainView checklist \(triggersChecklist?.id ?? 0)")

            Color.black.edgesIgnoringSafeArea(.all)
                    .statusBar(hidden: true)
                    .animateVmValue(value: state.isPurple, state: $isPurpleAnim)

            VStack {

                let timerData = state.timerData
                let timerColor = timerData.color.toColor()

                Text(state.title)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundColor(timerColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                Button(
                        action: {
                            vm.toggleIsPurple()
                        },
                        label: {
                            Text(timerData.title)
                                    .font(getTimerFont(size: 44))
                                    .foregroundColor(timerColor)
                        }
                )
                        .padding(.top, 13)

                if state.isTimerButtonsVisible {

                    let timerButtonsHeight = 32.0

                    HStack {

                        Button(
                                action: {
                                    vm.pauseTask()
                                },
                                label: {
                                    Image(systemName: "pause.fill")
                                            .foregroundColor(.black)
                                            .font(.system(size: 16))
                                }
                        )
                                .frame(width: timerButtonsHeight, height: timerButtonsHeight)
                                .background(roundedShape.fill(.white))

                        Button(
                                action: {
                                    state.timerData.restart()
                                },
                                label: {
                                    HStack {

                                        Image(systemName: "clock.arrow.circlepath")
                                                .foregroundColor(.black)
                                                .font(.system(size: 16, weight: .heavy))

                                        Text(state.timerData.restartText)
                                                .padding(.leading, 2)
                                                .padding(.trailing, 2)
                                                .font(.system(size: 19, weight: .bold))
                                                .foregroundColor(.black)
                                    }
                                }
                        )
                                .padding(.horizontal, 8)
                                .frame(height: timerButtonsHeight)
                                .background(roundedShape.fill(.white))
                                .padding(.leading, 10)
                    }
                            .padding(.top, 16)
                }

                ZStack {

                    let checklistUI = state.checklistUI

                    VStack {

                        let isImportantTasksExists = !state.importantTasks.isEmpty

                        if let checklistUI = checklistUI {
                            VStack(spacing: 0) {
                                ChecklistView(checklistUI: checklistUI)
                                FSDivider()
                            }
                        }

                        if isImportantTasksExists {
                            let listHeight: CGFloat =
                                    checklistUI == nil ? .infinity :
                                    (taskListContentPadding * 2.0) +
                                    (taskItemHeight * state.importantTasks.count.toDouble().limitMax(5.1))
                            ImportantTasksView(
                                    tasks: state.importantTasks
                            )
                                    .frame(height: listHeight)
                        }

                        if !isImportantTasksExists && checklistUI == nil {
                            Spacer()
                        }
                    }
                            .padding(.bottom, navAndTasksTextHeight)

                    if (state.isTasksVisible) {

                        VStack {
                            if let checklistUI = checklistUI {

                                Button(
                                        action: {
                                            vm.toggleIsTasksVisible()
                                        },
                                        label: {
                                            Text(checklistUI.titleToExpand)
                                                    .foregroundColor(.white)
                                                    .frame(maxWidth: .infinity)
                                                    .padding(.top, 6)
                                                    .padding(.bottom, 12)
                                        }
                                )
                                        .background(.black)

                                DividerBg()
                            }

                            TasksView()
                                    .clipped() // Fix list offset on IME open
                        }
                                .padding(.bottom, bottomNavigationHeight)
                    }
                }
            }

            //
            // Navigation

            HStack(alignment: .bottom) {

                Button(
                        action: {
                            timetoSheet.showActivitiesTimerSheet(
                                    isPresented: $isTimerActivitiesPresented,
                                    timerContext: nil,
                                    selectedActivity: nil,
                                    onStart: {
                                        isTimerActivitiesPresented = false
                                    }
                            )
                        },
                        label: {
                            VStack(spacing: 0) {
                                Spacer()
                                Image(systemName: "timer")
                                        .frame(height: menuIconSize)
                                        .foregroundColor(menuColor)
                                        .font(.system(size: 30, weight: .thin))
                                        .frame(maxWidth: .infinity)
                                        .frame(alignment: .bottom)
                            }
                        }
                )

                Button(
                        action: {
                            vm.toggleIsTasksVisible()
                        },
                        label: {

                            VStack {

                                if (!state.isTasksVisible) {

                                    Text(state.tasksText)
                                            .foregroundColor(menuColor)
                                            .font(.system(size: 15, weight: .regular))
                                            .padding(.top, 10)

                                    Spacer()
                                }

                                VStack(alignment: .center) {

                                    Text(state.timeOfTheDay)
                                            .foregroundColor(menuColor)
                                            .font(.system(size: 17, weight: .bold))

                                    HStack(spacing: 0) {

                                        let batteryTextColor = state.batteryTextColor.toColor()

                                        Image(systemName: "bolt.fill")
                                                .foregroundColor(batteryTextColor)
                                                .font(.system(size: 12, weight: .ultraLight))

                                        Text(state.batteryText)
                                                .foregroundColor(batteryTextColor)
                                                .font(.system(size: 13, weight: .regular))
                                                .padding(.trailing, 1)
                                    }
                                            .padding(.top, 2)
                                            .padding(.bottom, 1)
                                            .padding(.leading, 3)
                                            .padding(.trailing, 4)
                                            .background(
                                                    RoundedRectangle(cornerRadius: 99, style: .circular)
                                                            .fill(state.batteryBackground.toColor())
                                            )
                                }
                                        .padding(.top, 2)
                                        .frame(height: bottomNavigationHeight)
                            }
                                    .frame(maxWidth: .infinity)
                                    .background(state.isTasksVisible ? Color(.systemGray5) : .black)
                                    .cornerRadius(10, onTop: true, onBottom: true)
                        }
                )

                Button(
                        action: {
                            isSettingsSheetPresented = true
                        },
                        label: {
                            VStack(spacing: 0) {
                                Spacer()
                                Image(systemName: "ellipsis.circle")
                                        .frame(height: menuIconSize)
                                        .foregroundColor(menuColor)
                                        .font(.system(size: 30, weight: .thin))
                                        .frame(maxWidth: .infinity)
                            }
                        }
                )
            }
                    .frame(width: .infinity, height: state.isTasksVisible ? bottomNavigationHeight : navAndTasksTextHeight)
        }
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .onReceive(shortcutPublisher) { shortcut in
                    let swiftURL = URL(string: shortcut.uri)!
                    if !UIApplication.shared.canOpenURL(swiftURL) {
                        UtilsKt.showUiAlert(message: "Invalid shortcut link", reportApiText: nil)
                        return
                    }
                    UIApplication.shared.open(swiftURL)
                }
                .onReceive(checklistPublisher) { checklist in
                    triggersChecklist = checklist
                    isTriggersChecklistPresented = true
                }
                .sheetEnv(isPresented: $isTriggersChecklistPresented) {
                    if let checklist = triggersChecklist {
                        ChecklistDialog(isPresented: $isTriggersChecklistPresented, checklist: checklist)
                    }
                }
                .sheetEnv(
                        isPresented: $isSettingsSheetPresented
                ) {
                    SettingsSheet(isPresented: $isSettingsSheetPresented)
                }
                .onAppear {
                    MainView.lastInstance = self
                }
    }
}

private struct ChecklistView: View {

    let checklistUI: MainVM.ChecklistUI

    @State private var vScroll = 0

    var body: some View {

        VStack(spacing: 0) {

            FSDivider(isVisible: vScroll > 0)

            GeometryReader { proxy in

                ZStack(alignment: .center) {

                    HStack(alignment: .top, spacing: 0) {

                        let checkboxSize = 20.0
                        let checklistItemMinHeight = 46.0
                        let checklistDividerPadding = 12.0

                        ScrollViewWithVListener(showsIndicators: false, vScroll: $vScroll) {

                            VStack(spacing: 0) {

                                ForEach(checklistUI.itemsUI, id: \.item.id) { itemUI in

                                    Button(
                                            action: {
                                                itemUI.toggle()
                                            },
                                            label: {
                                                HStack(spacing: 0) {

                                                    Image(systemName: itemUI.item.isChecked ? "checkmark.square.fill" : "square")
                                                            .foregroundColor(Color.white)
                                                            .font(.system(size: checkboxSize, weight: .regular))
                                                            .padding(.trailing, checklistDividerPadding)

                                                    Text(itemUI.item.text)
                                                            .padding(.vertical, 4)
                                                            .foregroundColor(.white)
                                                            .font(.system(size: 18))
                                                }
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .frame(minHeight: checklistItemMinHeight)
                                                //                                                .background(Color.red)
                                            }
                                    )
                                }
                            }

                            Spacer()
                        }

                        let dividerGap = 8.0
                        Color(dividerColor)
                                .frame(width: onePx)
                                .frame(height: checklistItemMinHeight - dividerGap)
                                .padding(.top, dividerGap / 2)
                                .padding(.trailing, checklistDividerPadding)

                        let stateUI = checklistUI.stateUI
                        let stateIconResource: String = {
                            if stateUI is ChecklistStateUI.Completed { return "checkmark.square.fill" }
                            if stateUI is ChecklistStateUI.Empty { return "square" }
                            if stateUI is ChecklistStateUI.Partial { return "minus.square.fill" }
                            fatalError()
                        }()
                        Button(
                                action: {
                                    stateUI.onClick()
                                },
                                label: {
                                    Image(systemName: stateIconResource)
                                            .foregroundColor(Color.white)
                                            .font(.system(size: checkboxSize, weight: .regular))
                                            .padding(.trailing, checklistDividerPadding)
                                }
                        )
                                .frame(height: checklistItemMinHeight)
                    }
                            .frame(width: proxy.size.width * 0.80)
                }
                        .frame(maxWidth: .infinity)
            }
        }
                .padding(.top, 20)
    }
}

private struct ImportantTasksView: View {

    let tasks: [MainVM.ImportantTask]

    private let LIST_BOTTOM_ITEM_ID = "bottom_id"

    var body: some View {

        GeometryReader { geometry in

            ScrollViewReader { scrollProxy in

                ScrollView(showsIndicators: false) {

                    VStack(spacing: 0) {

                        Spacer()

                        ZStack {}
                                .frame(height: taskListContentPadding)

                        ForEach(tasks.reversed(), id: \.self.task.id) { importantTask in
                            ImportantTaskItem(importantTask: importantTask)
                        }

                        ZStack {}
                                .frame(height: taskListContentPadding)
                                .id(LIST_BOTTOM_ITEM_ID)
                    }
                            .frame(minHeight: geometry.size.height)
                }
                        .frame(maxWidth: .infinity)
                        .onAppear {
                            scrollProxy.scrollTo(LIST_BOTTOM_ITEM_ID)
                        }
            }
        }
    }
}

private struct ImportantTaskItem: View {

    let importantTask: MainVM.ImportantTask

    @State private var isSheetPresented = false

    @EnvironmentObject private var timetoSheet: TimetoSheet

    var body: some View {

        Button(
                action: {
                    importantTask.task.startIntervalForUI(
                            onStarted: {},
                            activitiesSheet: {
                                timetoSheet.showActivitiesTimerSheet(
                                        isPresented: $isSheetPresented,
                                        timerContext: importantTask.timerContext,
                                        selectedActivity: nil,
                                        onStart: {
                                            isSheetPresented = false
                                        }
                                )
                            },
                            timerSheet: { activity in
                                timetoSheet.showActivitiesTimerSheet(
                                        isPresented: $isSheetPresented,
                                        timerContext: importantTask.timerContext,
                                        selectedActivity: activity,
                                        onStart: {
                                            isSheetPresented = false
                                        }
                                )
                            }
                    )
                },
                label: {
                    HStack(spacing: 0) {

                        HStack(spacing: 0) {

                            Image(systemName: "calendar")
                                    .foregroundColor(Color.white)
                                    .font(.system(size: 15, weight: .light))
                                    .padding(.trailing, 3)

                            Text(importantTask.text)
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.white)
                        }
                                .padding(.horizontal, 6)
                                .frame(maxHeight: .infinity)
                                .background(
                                        RoundedRectangle(cornerRadius: 99, style: .circular)
                                                .fill(importantTask.backgroundColor.toColor())
                                )
                                .padding(.all, 1)
                                .background(
                                        RoundedRectangle(cornerRadius: 99, style: .circular)
                                                .fill(importantTask.borderColor.toColor())
                                )
                                .padding(.vertical, 4)
                                .padding(.horizontal, dividerPadding)
                    }
                            .frame(height: taskItemHeight)
                }
        )
    }
}

private struct FSDivider: View {

    var isVisible = true

    var body: some View {
        Color(isVisible ? dividerColor : .clear)
                .frame(height: onePx)
                .padding(.horizontal, dividerPadding)
    }
}