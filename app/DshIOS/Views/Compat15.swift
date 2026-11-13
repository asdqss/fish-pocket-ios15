import SwiftUI
import UIKit

// iOS 15.6 回退兼容层（yg/ios15-backport 分支）。
//
// 设计约束：
//  1. 只新增类型/修饰符，绝不重定义 SDK 同名类型（`ContentUnavailableView`、`LabeledContent`
//     这些名字在 iOS 17 SDK 里已存在，重定义会产生歧义或重复声明）。
//  2. 调用点逐个替换成 `Compat*` 名字，机械可查；这样 iOS 16/17 上走原生实现，
//     15.6 上走这里的降级实现，两边行为都能解释。
//  3. 每个 shim 都写清楚「在 iOS 15.6 上少掉了什么」，不要假装补齐。
//
// 完整清单与工作量见 docs/backport/ios15-plan.md。

// MARK: - 面板高度（presentationDetents 是 iOS 16）

enum CompatDetent {
    case medium
    case large
    case height(CGFloat)

    @available(iOS 16.0, *)
    var system: PresentationDetent {
        switch self {
        case .medium: return .medium
        case .large: return .large
        case .height(let h): return .height(h)
        }
    }
}

extension View {
    /// iOS 16 有 presentationDetents；15.6 上退回系统默认高度（全屏 sheet）。
    @ViewBuilder
    func compatDetents(_ detents: [CompatDetent]) -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDetents(Set(detents.map { $0.system }))
        } else {
            self
        }
    }

    /// 面板可拖动关闭：iOS 15 上 sheet 本来就能下滑关闭，这里只是占位。
    @ViewBuilder
    func compatDragIndicator() -> some View {
        if #available(iOS 16.0, *) {
            self.presentationDragIndicator(.visible)
        } else {
            self
        }
    }
}

// MARK: - 空态视图（ContentUnavailableView 是 iOS 17）

struct CompatUnavailable<LView: View, DView: View, AView: View>: View {
    private let label: LView
    private let description: DView
    private let actions: AView

    init(@ViewBuilder label: () -> LView,
         @ViewBuilder description: () -> DView,
         @ViewBuilder actions: () -> AView) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            label
            description
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            actions
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

// `CompatUnavailable("标题", systemImage: "icon")` 这类调用**不能**用
// extension 里的 `init` 实现：Swift 在解析 `CompatUnavailable(...)` 简写时，
// 不会拿扩展 `where` 子句里的等式约束去反推主泛型的实参，
// 结果就是 "generic parameter 'LView' could not be inferred"。
//
// 所以标题形态改用**静态工厂**：返回类型里三个泛型参数全是写死，
// 名字不再是 `init`，也不会和闭包形态抢重载。

extension CompatUnavailable where LView == CompatUnavailableLabel, DView == EmptyView, AView == EmptyView {
    /// 替 `ContentUnavailableView("标题", systemImage: "icon")`。
    static func title(_ title: String, systemImage: String) -> Self {
        CompatUnavailable<CompatUnavailableLabel, EmptyView, EmptyView>(
            label: { CompatUnavailableLabel(title: title, systemImage: systemImage) },
            description: { EmptyView() },
            actions: { EmptyView() })
    }
}

/// 「图标 + 标题」这一段空态标签，单独成类型，好让 `LView` 有名字可推导。
struct CompatUnavailableLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
        }
    }
}

extension CompatUnavailable where LView == CompatSearchLabel, DView == Text, AView == EmptyView {
    /// `ContentUnavailableView.search` 的等价物。
    static var search: CompatUnavailable<CompatSearchLabel, Text, EmptyView> {
        CompatUnavailable<CompatSearchLabel, Text, EmptyView>(
            label: { CompatSearchLabel() },
            description: { Text("没找到匹配的内容") },
            actions: { EmptyView() })
    }

    /// `ContentUnavailableView.search(text:)`：搜的是哪一串也写出来。
    static func search(text: String) -> CompatUnavailable<CompatSearchLabel, Text, EmptyView> {
        CompatUnavailable<CompatSearchLabel, Text, EmptyView>(
            label: { CompatSearchLabel() },
            description: { Text("没有与“\(text)”匹配的内容") },
            actions: { EmptyView() })
    }
}

struct CompatSearchLabel: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)
            Text("没有结果").font(.headline)
        }
    }
}

// MARK: - 分享（ShareLink 是 iOS 16）

/// ShareLink 的 15.6 等价物：点一下弹 UIActivityViewController。
/// 少了 ShareLink 的 Transferable 预览画质与进度（`preview:`），其余一致。
struct CompatShareButton<Content: View>: View {
    private let items: [Any]
    private let content: Content
    @State private var presented = false

    init(_ items: [Any], @ViewBuilder label: () -> Content) {
        self.items = items
        self.content = label()
    }

    var body: some View {
        Button { presented = true } label: { content }
            .background(ActivityPresenter(items: items, presented: $presented))
    }
}

private struct ActivityPresenter: UIViewControllerRepresentable {
    let items: [Any]
    @Binding var presented: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard presented, host.presentedViewController == nil else { return }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.completionWithItemsHandler = { _, _, _, _ in
            DispatchQueue.main.async { presented = false }
        }
        host.present(sheet, animated: true)
    }
}

// MARK: - 卡片列表（LabeledContent 是 iOS 16）

/// LabeledContent 的 15.6 等价物，只覆盖本仓库出现的两种形态：
/// `CompatLabeledContent("标题", value: 值)` 与 `CompatLabeledContent("标题") { 内容 }`。
struct CompatLabeledContent<Content: View>: View {
    private let title: Text
    private let content: Content

    /// 用 `StringProtocol` 接标题：字符串字面量、`String`、`Substring` 都能进，
    /// 且只有一个候选，不会出现 `LocalizedStringKey` + `String` 双重重载的歧义。
    init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content) {
        self.title = Text(String(title))
        self.content = content()
    }

    /// 标题本来就是 `LocalizedStringKey` 的调用点（要参与本地化查表）。
    init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = Text(title)
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            title.foregroundStyle(.secondary)
            Spacer(minLength: 12)
            content.multilineTextAlignment(.trailing)
        }
    }
}

extension CompatLabeledContent where Content == Text {
    // ⚠️ 只保留**一个** `value:` 入口。同时存在 `value: String` 和
    // `value: V where V: CustomStringConvertible` 时，传一个 `String` 变量
    // 会因 `String` 自身满足 `CustomStringConvertible` 而两个候选都成立 →
    // "ambiguous use of 'init(_:value:)'"（实测 17 处）。
    // 泛型版能接住 `String` / `Int` / `Double` / `Bool` 全部，所以只用它。
    // 没有 `value: String?` 重载：全仓的可选值在调用点都已 `?? "—"` 收口。
    init<S: StringProtocol, V: CustomStringConvertible>(_ title: S, value: V) {
        self.init(title) { Text(value.description) }
    }
}

    init(_ title: LocalizedStringKey, value: String) {
        self.init(title) { Text(value) }
    }

    init(_ title: LocalizedStringKey, value: String?) {
        self.init(title) { Text(value ?? "—") }
    }

    init<V: CustomStringConvertible>(_ title: LocalizedStringKey, value: V) {
        self.init(title) { Text(value.description) }
    }
}

// MARK: - 补充：调用点实际用到的重载
//
// 注意：泛型参数名必须与主类型的 `LView / DView / AView` 一致。
// 写成 `Label / Description / Actions` 会被当成未声明的类型，
// 报 "cannot find type 'Description' in scope"。

extension CompatUnavailable where DView == EmptyView {
    /// `ContentUnavailableView { Label } actions: { … }`：有按钮、没有说明。
    init(@ViewBuilder label: () -> LView, @ViewBuilder actions: () -> AView) {
        self.init(label: label, description: { EmptyView() }, actions: actions)
    }
}

extension CompatUnavailable where AView == EmptyView {
    init(@ViewBuilder label: () -> LView, @ViewBuilder description: () -> DView) {
        self.init(label: label, description: description, actions: { EmptyView() })
    }
}

extension CompatUnavailable where DView == EmptyView, AView == EmptyView {
    init(@ViewBuilder label: () -> LView) {
        self.init(label: label, description: { EmptyView() }, actions: { EmptyView() })
    }
}

extension CompatUnavailable where LView == CompatUnavailableLabel, DView == Text, AView == EmptyView {
    /// 替 `ContentUnavailableView("标题", systemImage: "icon", description: Text(...))`。
    /// 同 `title(_:systemImage:)`，用静态工厂而不是 init —— 见上文的说明。
    static func title(_ title: String, systemImage: String, description: Text) -> Self {
        CompatUnavailable<CompatUnavailableLabel, Text, EmptyView>(
            label: { CompatUnavailableLabel(title: title, systemImage: systemImage) },
            description: { description },
            actions: { EmptyView() })
    }
}

extension CompatLabeledContent where Content == Text {
    init(_ title: String, value: String?) {
        self.init(title) { Text(value ?? "—") }
    }

    init<V>(_ title: String, value: V) where V: CustomStringConvertible {
        self.init(title) { Text(value.description) }
    }
}

// MARK: - StoreKit 的 requestReview（iOS 16）降级

extension View {
    /// 15 上没有 `\@Environment(\.requestReview)`；退成直接打开 App Store 的评价页。
    func compatRequestReview(appID: String) {
        guard let url = URL(string: "https://apps.apple.com/app/id\(appID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - onChange(of:initial:_:)（iOS 17）

extension View {
    /// iOS 17 的 `onChange(of:initial:_:)`：15 上用 `onChange(of:perform:)` + 首次 `onAppear` 复现。
    func compatChange<V: Equatable>(of value: V, initial: Bool = false,
                                    _ action: @escaping (V) -> Void) -> some View {
        self.onChange(of: value, perform: action)
            .onAppear { if initial { action(value) } }
    }
}

// MARK: - 正则字面量（iOS 16）的替代

enum CompatRegex {
    /// 单次匹配：返回（整体范围，第一个捕获组）
    static func firstMatch(_ pattern: String, in text: String,
                           caseInsensitive: Bool = false) -> (range: Range<String.Index>, group: String?)? {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              let full = Range(m.range, in: text) else { return nil }
        var group: String?
        if m.numberOfRanges > 1, m.range(at: 1).location != NSNotFound, let r = Range(m.range(at: 1), in: text) {
            group = String(text[r])
        }
        return (full, group)
    }

    static func replacing(_ pattern: String, in text: String, with template: String = "",
                          caseInsensitive: Bool = false) -> String {
        var opts: NSRegularExpression.Options = []
        if caseInsensitive { opts.insert(.caseInsensitive) }
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return text }
        let ns = text as NSString
        return re.stringByReplacingMatches(in: text, options: [],
                                          range: NSRange(location: 0, length: ns.length), withTemplate: template)
    }
}
