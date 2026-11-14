import SwiftUI
import UIKit

// yg/ios15-backport：iOS 16/17 的 SwiftUI API 在 15.6 上的同名替身。
//
// 每个替身都只做一件事：让调用点保持原样，并在 15.6 上给出「行为上说得过去」的结果。
// 有损的地方都写在各自注释里，方便以后按需补。

// MARK: - NavigationStack（iOS 16）
//
// 部署目标 16.0：`NavigationStack` / `.navigationDestination` 都是 iOS 16 原生 API。

#if DSH_IOS15_LEGACY
/// 替 `NavigationStack`：15.6 上落到 `NavigationView`（`.stack` 样式，iPhone 上就是全屏推入）。
///
/// `path:` 版本接受绑定但**不参与路由**——15.6 没有 `navigationDestination(for:)` 的
/// 值驱动栈，那些页面改由各视图自己的 `NavigationLink(destination:)` 推入。
struct NavigationStack<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    init<Path>(path: Binding<Path>, @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        NavigationView { content }
            .navigationViewStyle(.stack)
    }
}

extension View {
    /// 替 `.navigationDestination(for:destination:)`：15.6 上不注册（见上）。
    func navigationDestination<V, D: View>(for type: V.Type,
                                           @ViewBuilder destination: @escaping (V) -> D) -> some View {
        self
    }

    /// `isPresented:` 版本能用 `NavigationLink(isActive:)` 顶上，行为接近原样。
    func navigationDestination<D: View>(isPresented: Binding<Bool>,
                                        @ViewBuilder destination: @escaping () -> D) -> some View {
        background(
            NavigationLink(isActive: isPresented, destination: { destination() }, label: { EmptyView() })
                .hidden()
        )
    }

    /// `item:` 版本没有对应机制，退成不推入。
    func navigationDestination<Item: Hashable, D: View>(item: Binding<Item?>,
                                                        @ViewBuilder destination: @escaping (Item) -> D) -> some View {
        self
    }
}
#endif  // DSH_IOS15_LEGACY

// MARK: - ShareLink / SharePreview（iOS 16）
//
// 部署目标 16.0：`ShareLink` / `SharePreview` 都是 iOS 16 原生 API。

#if DSH_IOS15_LEGACY
/// 替 `SharePreview`：15.6 上只是承接参数，不参与呈现。
struct SharePreview {
    let title: String

    init(_ title: String, image: Any? = nil) { self.title = title }
    init(_ title: LocalizedStringKey, image: Any? = nil) { self.title = String(describing: title) }
    init(_ title: Text, image: Any? = nil) { self.title = String(describing: title) }
}

/// 没有自定义标签时用的图标。
struct ShareIconLabel: View {
    var body: some View {
        Image(systemName: "square.and.arrow.up")
    }
}

/// 替 `ShareLink`：15.6 上用 `UIActivityViewController` 呈现。
struct ShareLink<Label: View>: View {
    private let payload: [Any]
    private let label: Label

    init<I>(item: I, subject: Text? = nil, message: Text? = nil,
            preview: SharePreview? = nil,
            @ViewBuilder label: () -> Label) {
        self.payload = SharePayload.activities(from: item)
        self.label = label()
    }

    init<I>(_ title: LocalizedStringKey, item: I, subject: Text? = nil, message: Text? = nil,
            preview: SharePreview? = nil,
            @ViewBuilder label: () -> Label) {
        self.payload = SharePayload.activities(from: item)
        self.label = label()
    }

    var body: some View {
        Button { SharePayload.present(payload) } label: { label }
    }
}

extension ShareLink where Label == ShareIconLabel {
    init<I>(item: I, subject: Text? = nil, message: Text? = nil, preview: SharePreview? = nil) {
        self.payload = SharePayload.activities(from: item)
        self.label = ShareIconLabel()
    }
}
#endif  // DSH_IOS15_LEGACY

/// 分享的运行时实现：`ShareLink` 在 16.0 上走系统原生，但 `Views/Compat15.swift`
/// 里的 `CompatShareButton` 仍然需要这套 `UIActivityViewController` 逻辑，所以不围进来。
enum SharePayload {
    /// 把「可分享的东西」翻成 `UIActivityViewController` 认识的对象。
    static func activities(from item: Any) -> [Any] {
        if let url = item as? URL { return [url] }
        if let image = item as? UIImage { return [image] }
        if let string = item as? String { return [string] }
        if let file = item as? MarkdownFile { return markdownFile(file) }
        if let data = item as? Data { return [data] }
        return []
    }

    /// `MarkdownFile` 写成临时 `.md` 再分享；文件名沿用它的 `name`。
    static func markdownFile(_ file: MarkdownFile) -> [Any] {
        let safe = file.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = safe.isEmpty ? "ds-markdown" : safe
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(base)
            .appendingPathExtension("md")
        guard (try? file.text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return [file.text] }
        return [url]
    }

    static func present(_ items: [Any]) {
        guard !items.isEmpty else { return }
        DispatchQueue.main.async {
            guard let top = topViewController() else { return }
            let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
            if let popover = controller.popoverPresentationController {
                popover.sourceView = top.view
                popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            top.present(controller, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene?.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

// MARK: - Grid / GridRow（iOS 16）
//
// 部署目标 16.0：`Grid` / `GridRow` / `.gridCellColumns` 都是 iOS 16 原生 API。

#if DSH_IOS15_LEGACY
private struct GridSpacingKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var compatGridSpacing: CGFloat? {
        get { self[GridSpacingKey.self] }
        set { self[GridSpacingKey.self] = newValue }
    }
}

/// 替 `Grid`：15.6 上是「行叠起来」的 `VStack`，列宽不再自动对齐（表格类内容会略微参差）。
struct Grid<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let verticalSpacing: CGFloat?
    private let content: Content

    init(alignment: HorizontalAlignment = .center,
         horizontalSpacing: CGFloat? = nil,
         verticalSpacing: CGFloat? = nil,
         @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.verticalSpacing = verticalSpacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: verticalSpacing) { content }
    }
}

/// 替 `GridRow`：一行 `HStack`。
struct GridRow<Content: View>: View {
    @Environment(\.compatGridSpacing) private var spacing
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) { content }
    }
}
#endif  // DSH_IOS15_LEGACY

extension View {
    /// 替 `.onGeometryChange(for:of:action:)`（iOS 16/17）：用 `GeometryReader` 量同一件事。
    func onGeometryChange<T: Equatable>(for type: T.Type,
                                        of transform: @escaping (GeometryProxy) -> T,
                                        action: @escaping (T) -> Void) -> some View {
        modifier(CompatGeometryChange(transform: transform, action: action))
    }
}

struct CompatGeometryChange<T: Equatable>: ViewModifier {
    let transform: (GeometryProxy) -> T
    let action: (T) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let value = transform(proxy)
                Color.clear
                    .onAppear { action(value) }
                    .onChange(of: value, perform: { new in action(new) })
            }
        )
    }
}

// MARK: - ViewThatFits（iOS 16）
//
// 部署目标 16.0：`ViewThatFits` 是 iOS 16 原生 API。

#if DSH_IOS15_LEGACY
/// 替 `ViewThatFits`：15.6 上取**最后**一个候选——这几处调用都把「更紧凑、总能放下」
/// 的那一个写在最后（横向 ScrollView / 纵向堆叠），所以不会出现裁切。
struct ViewThatFits<Content: View>: View {
    private let content: Content

    init(in axes: Axis.Set = [.horizontal, .vertical], @ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        _VariadicView.Tree(LastChild()) { content }
    }

    private struct LastChild: _VariadicView.MultiViewRoot {
        func body(children: _VariadicView.Children) -> some View {
            if let last = children.last { last } else { EmptyView() }
        }
    }
}
#endif  // DSH_IOS15_LEGACY

// MARK: - withAnimation(_:_:completion:)（iOS 17）

/// 替 iOS 17 的带完成回调版本：动画照做，完成回调按动画时长稍后触发。
@discardableResult
func withAnimation<Result>(_ animation: Animation? = .default,
                           _ body: () throws -> Result,
                           completion: @escaping () -> Void) rethrows -> Result {
    let result = try withAnimation(animation, body)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: completion)
    return result
}

// MARK: - Path.subtracting(_:eoFill:)（iOS 17）

extension Path {
    /// 15.6 没有路径布尔运算。把两个路径叠在一起（非零环绕填充），
    /// 对「挖洞」的用法会画成实体，对「取并」的用法完全正确。
    func subtracting(_ other: Path, eoFill: Bool = false) -> Path {
        var combined = self
        combined.addPath(other)
        return combined
    }
}

// MARK: - 少量 iOS 16 修饰符的降级
//
// 注意：部署目标是 16.0 时，下面这几个**全部是 iOS 16 原生已有的 API**。
// 再定义一遍同名 shim 会让每个调用点变成 "ambiguous use of ..."。
// 所以用 `#if` 围起来，只在 15.6 上生效。

#if DSH_IOS15_LEGACY
extension View {
    /// `.scrollContentBackground(.hidden)`（iOS 16）：15.6 上原本就没有底色，忽略即可。
    func scrollContentBackground(_ visibility: Visibility) -> some View { self }

    /// `.toolbarBackground(_:for:)`（iOS 16）。
    func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacement...) -> some View { self }
}
#endif  // DSH_IOS15_LEGACY

// 以下这些 API 在 **16.0 上仍然不存在**（16.4 / 17 才有），所以必须保留降级实现，
// 但**不能占用系统名字**——改叫 compat*，调用点跟着改。
extension View {
    /// 替 `.presentationBackground(_:)`（iOS 16.4）：
    /// 16.0 上没有这个修饰符，sheet 背景沿用系统默认。
    /// 两个重载分别在 `ShapeStyle` 和 `View` 上，调用 `Palette.background`（一个 Color，
    /// 两者都满足）时会歧义 —— 统一收敛成只接 `ShapeStyle`，`View` 版本改名。
    func compatPresentationBackground<S: ShapeStyle>(_ style: S) -> some View { self }

    /// 替 `.presentationBackground(_:)` 传一个 View 的情况。
    func compatPresentationBackgroundView<V: View>(_ view: V) -> some View { self }

    /// 替 `.presentationBackgroundInteraction(_:)`（iOS 16.4）。
    func compatPresentationBackgroundInteraction(_ interaction: PresentationBackgroundInteraction) -> some View { self }

    /// 替 `.defaultScrollAnchor(_:)` / `.defaultScrollAnchor(_:for:)`（iOS 17）。
    func compatDefaultScrollAnchor(_ anchor: UnitPoint?) -> some View { self }
    func compatDefaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View { self }

    /// 替 `.scrollBounceBehavior(_:axes:)`（iOS 16.4）。
    func compatScrollBounceBehavior(_ behavior: CompatScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { self }

    /// 替 `.scrollIndicatorsFlash(onAppear:)`（iOS 17）。
    func compatScrollIndicatorsFlash(onAppear: Bool = false) -> some View { self }

    /// 替 `.scrollClipDisabled(_:)`（iOS 17）。
    func compatScrollClipDisabled(_ disabled: Bool = true) -> some View { self }
}

/// 替 `ScrollBounceBehavior`（iOS 16.4）。
enum CompatScrollBounceBehavior: Hashable {
    case automatic, always, basedOnSize
}

/// 替 `PresentationBackgroundInteraction`（iOS 16.4）。
enum PresentationBackgroundInteraction: Hashable {
    case automatic, enabled, disabled
}

/// 替 `ScrollAnchorRole`（iOS 17）。
enum ScrollAnchorRole: Hashable {
    case initialOffset, sizeChanges, alignment
}

extension View {
    /// 替 `.navigationDestination(item:destination:)`（iOS 17）。
    /// 16.0 上退成「值为非 nil 时用 `NavigationLink(isActive:)` 推入」。
    func compatNavigationDestination<Item: Hashable, D: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> D
    ) -> some View {
        background(
            NavigationLink(
                isActive: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                ),
                destination: {
                    if let value = item.wrappedValue { destination(value) } else { EmptyView() }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
    }
}

// MARK: - Swift Charts（iOS 16）

/// 15.6 上没有 Swift Charts。图表元素退成「按值排序的横向条形 + 类目/系列文字」：
/// 数值、对比和趋势都还在，只是没有坐标轴和曲线。
struct CompatChart15: View {
    struct Value: Identifiable {
        let id = UUID()
        let category: String
        let series: String
        let value: Double
    }

    let values: [Value]

    private var peak: Double { values.map { abs($0.value) }.max() ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(values.sorted { $0.value > $1.value }) { item in
                HStack(spacing: 8) {
                    Text(item.category)
                        .font(.caption)
                        .lineLimit(1)
                        .frame(width: 72, alignment: .leading)
                    GeometryReader { proxy in
                        let ratio = peak > 0 ? max(0, item.value) / peak : 0
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Palette.ink.opacity(0.7))
                            .frame(width: max(2, proxy.size.width * ratio))
                    }
                    .frame(height: 10)
                    Text(item.value.formatted(.number.precision(.fractionLength(0...2))))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !item.series.isEmpty {
                        Text(item.series).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - ScrollDismissesKeyboardMode / scrollDismissesKeyboard（iOS 16）
//
// 部署目标 16.0：`ScrollDismissesKeyboardMode` 是 iOS 16 原生类型。

#if DSH_IOS15_LEGACY
/// 替 `ScrollDismissesKeyboardMode`：15.6 上没有这个开关，值只用来接住调用点。
enum ScrollDismissesKeyboardMode {
    case immediately, interactively, never, automatically
}

extension View {
    /// 15.6：滚动收键盘的默认行为最接近 `.interactively`，这里不再额外处理。
    func scrollDismissesKeyboard(_ mode: ScrollDismissesKeyboardMode) -> some View { self }
}
#endif  // DSH_IOS15_LEGACY

// MARK: - ToolbarPlacement / toolbar(_:for:)（iOS 16）
//
// 部署目标 16.0：`ToolbarPlacement`、`.toolbar(_:for:)` 都是 iOS 16 原生 API。
// 再定义同名类型会让 `.navigationBar` 变成歧义引用，所以整块只在 15.6 生效。

#if DSH_IOS15_LEGACY
/// 替 `ToolbarPlacement`：只区分导航栏，其余位置在 15.6 上无对应物。
struct ToolbarPlacement: Hashable {
    private let name: String
    private init(_ name: String) { self.name = name }

    static let automatic = ToolbarPlacement("automatic")
    static let navigationBar = ToolbarPlacement("navigationBar")
    static let bottomBar = ToolbarPlacement("bottomBar")
    static let tabBar = ToolbarPlacement("tabBar")
}

extension View {
    /// `.toolbar(.hidden, for: .navigationBar)`：15.6 上翻成 `navigationBarHidden`。
    func toolbar(_ visibility: Visibility, for placements: ToolbarPlacement...) -> some View {
        modifier(CompatToolbarVisibility(visibility: visibility, placements: placements))
    }
}

struct CompatToolbarVisibility: ViewModifier {
    let visibility: Visibility
    let placements: [ToolbarPlacement]

    func body(content: Content) -> some View {
        if placements.contains(.navigationBar) {
            content.navigationBarHidden(visibility == .hidden)
        } else {
            content
        }
    }
}
#endif  // DSH_IOS15_LEGACY

// MARK: - 正则（15.6 没有 `Regex` 字面量）

enum CompatRegex15 {
    /// 取第一个匹配的全部分组（下标 0 是整体）。不支持匹配返回 nil。
    static func groups(_ pattern: String, in text: String, anchorsLines: Bool = false) -> [String]? {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    /// 按正则切开（等价 `split(separator: Regex)`），丢掉空段。
    static func split(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [text] }
        let ns = text as NSString
        var pieces: [String] = []
        var cursor = 0
        regex.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            pieces.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        pieces.append(ns.substring(from: cursor))
        return pieces.filter { !$0.isEmpty }
    }

    /// 是否有一处匹配。
    static func contains(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// 整个字符串是否就是这一条（等价 `wholeMatch`）。
    static func wholeMatches(_ pattern: String, in text: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return match.range == range
    }

    /// 正则替换，模板里用 `$1` 这种分组引用（等价 `replacing(_:with:)`）。
    static func replacing(_ pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// 匹配到的整段之后的内容（没有匹配返回 nil）。
    static func afterHeader(_ pattern: String, in text: String, anchorsLines: Bool = false) -> String? {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let end = Range(match.range, in: text)?.upperBound else { return nil }
        return String(text[end...])
    }

    /// 所有匹配的第一个分组。
    static func firstGroups(_ pattern: String, in text: String, anchorsLines: Bool = false) -> [String] {
        var options: NSRegularExpression.Options = []
        if anchorsLines { options.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }
}

// MARK: - onChange（iOS 17 的双参版本）
//
// ⚠️ 不要在这里定义 `func onChange(of:_:)`。
// 部署目标 16.0 时，系统的 `onChange(of:_:)`（iOS 17）已经在候选里，
// 再叠加一个同签名的扩展会让**每一个** `.onChange(of: x, perform: { _ in  ... })` 变成
// "ambiguous use of 'onChange'"，编译器提示的解法是：
//   "use an explicit argument label instead of a trailing closure
//    to call 'onChange(of:perform:)'"
// 也就是调用点写 `.onChange(of: x, perform: { _ in  ... })` —— 显式标签就唯一了。
//
// 需要 `initial:` 语义的调用点走 Views/Compat15.swift 的 `compatChange`。

// MARK: - Path.union(_:eoFill:)（iOS 17）

extension Path {
    /// 15.6 没有路径布尔运算：直接叠加（对「合并」的用法等价）。
    func union(_ other: Path, eoFill: Bool = false) -> Path {
        var combined = self
        combined.addPath(other)
        return combined
    }
}

// MARK: - ScrollBounceBehavior / scrollBounceBehavior（iOS 16.4）
//
// 部署目标 16.0：这两个在 iOS 16.4+ 是原生 API，不能再定义同名 shim。

#if DSH_IOS15_LEGACY
struct ScrollBounceBehavior {
    private init() {}
    static let automatic = ScrollBounceBehavior()
    static let always = ScrollBounceBehavior()
    static let basedOnSize = ScrollBounceBehavior()
}

extension View {
    /// 15.6：默认弹性行为就是「总是可以」，这里不额外处理。
    func scrollBounceBehavior(_ behavior: ScrollBounceBehavior, axes: Axis.Set = [.vertical]) -> some View { self }
}

// MARK: - presentationDragIndicator（iOS 16）

extension View {
    /// 15.6 的 sheet 没有可关的抓手，忽略。
    func presentationDragIndicator(_ visibility: Visibility) -> some View { self }
}
#endif  // DSH_IOS15_LEGACY

// MARK: - TextField(_, text:, axis:)（iOS 16）

/// 替 `TextField(_:text:axis: .vertical)`：15.6 的多行输入只有 `TextEditor`，
/// 占位文字自己画。高度随内容长，外面仍可用 `.frame` 或容器约束。
struct CompatTextField: View {
    private let title: Text
    @Binding private var text: String
    private var minHeight: CGFloat = 34

    init(_ titleKey: LocalizedStringKey, text: Binding<String>) {
        self.title = Text(titleKey)
        self._text = text
    }

    init(_ title: String, text: Binding<String>) {
        self.title = Text(title)
        self._text = text
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .frame(minHeight: minHeight)
                .scrollContentBackground(.hidden)
            if text.isEmpty {
                title
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - inspector（iOS 17）

/// 替 `.inspector(isPresented:content:)`：iOS 17 才有右侧常驻面板。
/// 15.6 / 16.0 上落到 `HStack` —— 内容放在主视图右边、按 `idealWidth` 固定宽度。
/// 少掉的是：可拖动的分隔条、`.inspectorColumnWidth` 的 min/max 拉伸、
/// 以及 inspector 独立于主视图的滚动位置。
///
/// 与原生一样，`isPresented` 为 false 时**不构建内容**，
/// 这样里面的 toolbar 不会漏到主视图的导航栏上。
extension View {
    /// 替 `.inspector(isPresented:content:)`（iOS 17）。
    ///
    /// ⚠️ 不要在这里套 `HStack`。系统 `.inspector` 在 iPhone 上什么都不做，
    /// 只是把 `self` 原样返回；而套一层 `HStack` 会让 `self`（整个聊天页，含
    /// `ScrollView` + `safeAreaInset`）失去"撑满父容器"的语义：
    /// `ScrollView` 在 `HStack` 里高度收缩到内容高度（空会话为 0），
    /// 于是 `safeAreaInset` 的输入框被推到整屏——真机上就是"输入框占满页面、
    /// 会话内容看不见"。所以未展开时直接返回 `self`，不引入新容器。
    @ViewBuilder
    func compatInspector<V: View>(isPresented: Bool,
                                  @ViewBuilder content: @escaping () -> V) -> some View {
        if isPresented {
            HStack(spacing: 0) {
                self
                Divider()
                content()
            }
        } else {
            self
        }
    }

    /// 接受 `Binding<Bool>` 的版本：上游 `.inspector(isPresented:)` 收的就是 Binding，
    /// 大部分调用点传的是 `workbenchShown(...)` 这类计算出来的 Binding。
    /// 同样：关闭时直接返回 `self`，不套 `HStack`。
    @ViewBuilder
    func compatInspector<V: View>(isPresented: Binding<Bool>,
                                  @ViewBuilder content: @escaping () -> V) -> some View {
        if isPresented.wrappedValue {
            HStack(spacing: 0) {
                self
                Divider()
                content()
            }
        } else {
            self
        }
    }

    /// 替 `.inspectorColumnWidth(min:ideal:max:)`：`HStack` 布局下只认 `ideal`。
    func compatInspectorColumnWidth(min: CGFloat = 0, ideal: CGFloat, max: CGFloat = .infinity) -> some View {
        frame(minWidth: min, idealWidth: ideal, maxWidth: max)
    }
}
