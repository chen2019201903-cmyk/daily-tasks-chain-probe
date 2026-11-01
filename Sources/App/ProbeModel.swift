import Foundation
import Combine
import UserNotifications

@MainActor
final class ProbeModel: ObservableObject {
    @Published private(set) var marker: ProbeMarker?
    @Published private(set) var storageStatus = "正在读取测试标记"
    @Published private(set) var storageFailed = false
    @Published private(set) var busy = false
    @Published private(set) var permission = "尚未检查"
    @Published private(set) var notificationStatus = "尚未安排测试通知"
    @Published private(set) var pendingCount = 0
    @Published private(set) var deliveredCount = 0
    @Published private(set) var nextFireDate: Date?
    @Published private(set) var checkedAt: Date?

    private var store: MarkerStore?
    private let center = UNUserNotificationCenter.current()
    private let notificationID = "chainprobe.single-test"

    var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
    }

    var variant: String {
        Bundle.main.object(forInfoDictionaryKey: "ProbeVariant") as? String ?? "未知"
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
    }

    init() { reloadMarker() }

    private func resolveStore() throws -> MarkerStore {
        if let store { return store }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let resolved = MarkerStore(directory: support.appendingPathComponent("ChainProbe", isDirectory: true))
        store = resolved
        return resolved
    }

    func reloadMarker() {
        do {
            marker = try resolveStore().load()
            storageFailed = false
            storageStatus = marker == nil ? "尚无标记，首次安装后点下方按钮创建。" : "已从磁盘读回标记，请与更新前记录核对。"
        } catch {
            marker = nil
            storageFailed = true
            storageStatus = "读取失败，未重置数据：\(error.localizedDescription)"
        }
    }

    func createMarker() {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            marker = try resolveStore().createIfMissing()
            storageFailed = false
            storageStatus = "标记已保存并读回校验；后续更新、续签不要卸载此 App。"
        } catch {
            storageFailed = true
            storageStatus = "保存失败，未自动重置原数据：\(error.localizedDescription)"
        }
    }

    func refresh() async {
        // The button actions hold busy across awaits; a foreground refresh cannot
        // interleave and overwrite their displayed result with an older snapshot.
        guard !busy else { return }
        busy = true
        defer { busy = false }
        reloadMarker()
        await readNotificationState()
    }

    private func readNotificationState() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: permission = "尚未申请"
        case .denied: permission = "系统未允许"
        case .authorized: permission = "已允许"
        case .provisional: permission = "临时静默授权"
        case .ephemeral: permission = "临时授权"
        @unknown default: permission = "未知状态"
        }
        let pending = await center.pendingNotificationRequests().filter { $0.identifier == notificationID }
        let delivered = await center.deliveredNotifications().filter { $0.request.identifier == notificationID }
        pendingCount = pending.count
        deliveredCount = delivered.count
        nextFireDate = (pending.first?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
        checkedAt = Date()
    }

    func scheduleNotification() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound])
            guard allowed else {
                notificationStatus = "系统未允许通知。请在 iPhone 设置中检查后重试。"
                await readNotificationState()
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "链路验证 · 构建 \(variant)"
            content.body = "30 秒测试通知。请记录锁屏是否实际显示。"
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: notificationID,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
            )
            try await center.add(request)
            await readNotificationState()
            notificationStatus = pendingCount == 1
                ? "已核对 1 条待处理通知。现在回到桌面并锁屏，等待约 30 秒。"
                : "添加后未找到待处理通知，请重试并保留实际结果。"
        } catch {
            notificationStatus = "安排失败：\(error.localizedDescription)"
            await readNotificationState()
        }
    }

    func cancelNotification() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        await readNotificationState()
        notificationStatus = pendingCount == 0
            ? "待处理数为 0。请等到原触发时间，人工确认未收到新通知。"
            : "仍检测到待处理通知，请再次刷新核对。"
        // Do not clear delivered notification history.
    }

    var report: String {
        let iso = ISO8601DateFormatter()
        let markerID = marker?.id.uuidString ?? "无可读标记"
        let created = marker.map { iso.string(from: $0.createdAt) } ?? "—"
        let next = nextFireDate.map { iso.string(from: $0) } ?? "—"
        return """
        链路验证摘要（不等于自动验收通过）
        生成时刻：\(iso.string(from: Date()))
        版本：\(version)，构建：\(build)，变体：\(variant)
        Bundle ID：\(Bundle.main.bundleIdentifier ?? "未知")
        标记：\(markerID)
        创建时刻：\(created)
        存储状态：\(storageStatus)
        通知授权：\(permission)
        待处理：\(pendingCount)，通知中心保留：\(deliveredCount)
        下一次触发（UTC）：\(next)
        通知状态：\(notificationStatus)
        锁屏实际显示、更新和续签结果：需要人工填写。
        """
    }
}
