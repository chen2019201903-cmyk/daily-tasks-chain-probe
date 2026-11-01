import SwiftUI
import UIKit
import UserNotifications

final class ProbeAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
}

@main
struct ChainProbeApp: App {
    @UIApplicationDelegateAdaptor(ProbeAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup { ProbeView() }
    }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("当前构建") {
                    LabeledContent("变体", value: model.variant)
                    LabeledContent("构建号", value: model.build)
                    LabeledContent("版本", value: model.version)
                    Text("仅验证安装、数据保留与通知，不包含任务打卡功能。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("持久化标记") {
                    if let marker = model.marker {
                        Text(marker.id.uuidString)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                        LabeledContent("创建于") {
                            Text(marker.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                    }
                    Text(model.storageStatus)
                        .font(.footnote)
                        .foregroundStyle(model.storageFailed ? Color.red : Color.secondary)
                    Button("首次创建测试标记") { model.createMarker() }
                        .disabled(model.busy || model.marker != nil || model.storageFailed)
                    Text("创建后保存摘要；结束 App 重开、覆盖安装 B、续签后均应显示原标记。不要卸载 App。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("单条本地通知") {
                    LabeledContent("授权", value: model.permission)
                    LabeledContent("待处理", value: String(model.pendingCount))
                    LabeledContent("通知中心保留", value: String(model.deliveredCount))
                    if let fireDate = model.nextFireDate {
                        LabeledContent("预计触发") {
                            Text(fireDate, format: .dateTime.hour().minute().second())
                        }
                    }
                    Text("时间按设备当前时区显示；本探针使用相对 30 秒触发。")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("安排 30 秒后通知") {
                        Task { await model.scheduleNotification() }
                    }.disabled(model.busy)
                    Button("取消待处理测试通知") {
                        Task { await model.cancelNotification() }
                    }.disabled(model.busy)
                    Text(model.notificationStatus).font(.footnote)
                    Text("待处理数归零不代表已看到横幅；锁屏送达与取消效果需要人工确认。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("验收记录") {
                    Button("重新读取标记与通知状态") {
                        Task { await model.refresh() }
                    }.disabled(model.busy)
                    ShareLink(item: model.report) {
                        Label("分享验收摘要", systemImage: "square.and.arrow.up")
                    }.disabled(model.busy)
                    if let checkedAt = model.checkedAt {
                        LabeledContent("状态检查于") {
                            Text(checkedAt, format: .dateTime.hour().minute().second())
                        }
                    }
                }
            }
            .navigationTitle("链路验证")
            .task { await model.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
        }
    }
}
