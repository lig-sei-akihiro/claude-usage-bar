import AppKit
import Combine
import SwiftUI
import ClaudeUsageBarCore

/// `NSStatusItem` を所有する。`BarTitleFormatter` が生成する色分け済みのバータイトルを描画し、
/// `SettingsStore.refreshInterval` を基準にした更新タイマーを回し、`AppModel.snapshot` を
/// 駆動して、ポップオーバーと設定ウィンドウを表示する。
@MainActor
final class StatusItemController {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var settingsWindow: NSWindow?
    private var refreshTimer: Timer?
    private var settingsCancellable: AnyCancellable?
    private var isRefreshing = false

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        self.popover = NSPopover()
        popover.behavior = .transient
        // NSPopover の「contentSize の罠」に対する定番の対処。NSPopover は既定で 320x320 に
        // なり、それより背の高い SwiftUI コンテンツを黙ってクリップしてしまう。sizingOptions =
        // .preferredContentSize を指定すると hosting controller が SwiftUI の理想サイズを報告し、
        // ポップオーバーが内容に合わせて自動リサイズされる(クリップもスクロールも不要になる)。
        let hosting = NSHostingController(rootView: PopoverView().environmentObject(model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        model.refreshAction = { [weak self] in self?.refresh() }
        model.openSettingsAction = { [weak self] in self?.openSettings() }
        model.quitAction = { NSApp.terminate(nil) }

        // 表示/更新のオプションが変わったら、タイトルを再描画してタイマーを組み直す。
        settingsCancellable = model.settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                self?.updateBar()
                self?.scheduleTimer()
            }

        updateBar()
        scheduleTimer()
    }

    // MARK: ポップオーバー

    /// 左クリックでポップオーバーを開閉する(主たる UI)。右クリックでは素のメニューを表示し、
    /// ポップオーバーが使えないときでも Settings/Quit に到達できるようにする。
    @objc private func handleClick(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refreshFromMenu), keyEquivalent: "r").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quitFromMenu), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func refreshFromMenu() { model.refresh() }
    @objc private func openSettingsFromMenu() { model.openSettings() }
    @objc private func quitFromMenu() { model.quit() }

    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: 設定ウィンドウ

    private func openSettings() {
        popover.performClose(nil)

        // 固定サイズのウィンドウ。`sizingOptions = []` は hosting view が SwiftUI コンテンツに
        // 合わせてウィンドウをリサイズするのを止める。以前はこれにより、ウィンドウが画面上端の外
        // まで伸びたり、空のペインに縮んだりしていた。コンテンツは固定フレームを埋め、グループ化
        // された Form はそれより高ければスクロールする。
        let hostingView = NSHostingView(
            rootView: SettingsView(settings: model.settings, accounts: model.snapshot.accounts)
        )
        hostingView.sizingOptions = []

        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            // タイトル文字は表示しない。フォーム自体にアイコン + 名前のヘッダがあるため、ウィンドウ
            // のタイトル文字は冗長。標準のタイトルバー(信号機ボタン / ドラッグ)は残し、文字だけ
            // 隠す。(`title` は Window メニュー / アクセシビリティ用に設定したままにする。)
            window.title = "Settings"
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            // Spaces をまたいでユーザーに追従する。再表示時に、最初に現れた Space へ戻るのではなく、
            // 現在アクティブなデスクトップにウィンドウを持ってくる。
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.center()
            settingsWindow = window
        }
        window.contentView = hostingView

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: 更新

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        model.isRefreshing = true
        Task { @MainActor in
            let fresh = await UsageService().snapshot()
            // 一時的にエラーになっただけのアカウントについては、直近の既知の値を保持する。
            model.snapshot = fresh.retainingWindows(from: model.snapshot)
            model.isRefreshing = false
            isRefreshing = false
            updateBar()
        }
    }

    // MARK: タイマー

    private func scheduleTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        let seconds = model.settings.refreshInterval.rawValue
        guard seconds > 0 else { return }

        let timer = Timer(timeInterval: TimeInterval(seconds), repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    // MARK: バーのタイトル

    private func updateBar() {
        guard let button = statusItem.button else { return }

        let settings = model.settings.displaySettings
        let title = BarTitleFormatter.make(from: model.snapshot, settings: settings)

        // メニューバーのライト/ダーク状態はアプリの appearance ではなく壁紙に従う。そこで
        // severity パレットは status button 自身の appearance に対して解決する。さもないと
        // 適応的な色が誤ったバリアントを選んでしまう。
        let appearance = button.effectiveAppearance

        // Clawd(マスコット)とミニ使用量ゲージが常にステータスアイテムの先頭に立ち、アプリ
        // アイコンと呼応する。共有パレットの(最も深刻な)severity で着色し、ゲージはライブの
        // 使用量まで満ちる。
        let glyph = ClawdGlyph.image(
            fraction: BarTitleFormatter.representativeFraction(from: model.snapshot, settings: settings),
            color: SeverityColor.ns(title.severity).resolved(for: appearance))
        button.contentTintColor = nil

        let hasText = settings.showBarText && !title.text.isEmpty
        // アイコンとテキストの両方を消すとステータスアイテムが空になり、クリックする的すら
        // 無くなる。テキストが出ないときは `showBarIcon` の設定に関わらずアイコンを描き、常に
        // 何かがメニューバーに残るようにする(UI 側でも両方オフにはできないよう抑止している)。
        let showIcon = model.settings.showBarIcon || !hasText

        if hasText {
            if title.text.contains("\n") {
                // 積み重ね表示の行。グリフと両方の行を、メニューバーの高さに合わせた 1 枚の画像
                // に描く。素の複数行 attributedTitle では下端に余白が残っていたが、自前で画像を
                // 描くことでそれを取り除き、フォントを大きくできる。各行のパーセンテージはその行
                // 自身の severity で着色する。
                let lines = BarTitleFormatter.allLines(from: model.snapshot, settings: settings)
                button.attributedTitle = NSAttributedString(string: "")
                button.image = Self.stackedTitleImage(lines: lines, leadingGlyph: showIcon ? glyph : nil, appearance: appearance)
                button.imagePosition = .imageOnly
            } else {
                button.image = showIcon ? glyph : nil
                button.imagePosition = showIcon ? .imageLeading : .noImage
                button.attributedTitle = Self.barLine(
                    title.text, severity: title.severity,
                    font: .monospacedDigitSystemFont(ofSize: 12, weight: .regular),
                    appearance: appearance)
            }
        } else {
            // アイコンのみモード。Clawd + ゲージがステータスアイテムのすべてになる。
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            button.image = glyph
        }
    }

    /// 属性付きのステータスバー行。基となるテキストは主ラベルの色で描き、パーセンテージの
    /// トークンだけが severity の色(緑 → 橙 → 赤)をとる。アカウント/メトリクスのラベルと
    /// リセット時刻はラベル色のまま残す。
    ///
    /// どちらの色も `appearance` ―― 呼び出し側が status button から渡す *ステータスバー自身* の
    /// appearance ―― に対して解決する。メニューバーのライト/ダーク状態は壁紙で決まり、システムの
    /// テーマと食い違うことがある。そのため描画時に解決させると `labelColor` はテーマに従ってしまい、
    /// 実際のメニューバー背景に対して暗い背景に暗い文字(または明るい背景に明るい文字)になりかねない。
    static func barLine(_ text: String, severity: BarSeverity, font: NSFont,
                        paragraph: NSParagraphStyle? = nil,
                        appearance: NSAppearance? = nil) -> NSAttributedString {
        let baseColor = NSColor.labelColor.resolved(for: appearance)
        var base: [NSAttributedString.Key: Any] = [.foregroundColor: baseColor, .font: font]
        if let paragraph { base[.paragraphStyle] = paragraph }
        let attr = NSMutableAttributedString(string: text, attributes: base)
        if let range = percentRange(in: text) {
            let color = SeverityColor.ns(severity).resolved(for: appearance)
            attr.addAttribute(.foregroundColor, value: color, range: range)
        }
        return attr
    }

    /// 「NN%」(または「NN」)というパーセンテージトークンの範囲。行の *head*( " · " のリセット
    /// より前の全体)の末尾に続く数字列を指す。値は常に head の最後のトークンなので、`.all` モード
    /// で数字を含むアカウントラベル(例えば "v2 30%" の "2")の途中の数字に当たることも、リセット
    /// 時刻の数字に当たることもない。
    private static func percentRange(in text: String) -> NSRange? {
        let ns = text as NSString
        let sep = ns.range(of: " · ")
        let head = sep.location == NSNotFound ? text : ns.substring(to: sep.location)
        guard let re = try? NSRegularExpression(pattern: #"\d+%?$"#) else { return nil }
        return re.firstMatch(in: head, range: NSRange(location: 0, length: (head as NSString).length))?.range
    }

    /// 任意の先頭グリフと積み重ねた複数行を、メニューバーの高さに合わせた画像に、縦方向は中央
    /// 揃えで描画する。各行のパーセンテージはそれぞれの severity 色を保つ。レイアウトは 1 回の
    /// 複数行描画なので、行間が安定する。
    private static func stackedTitleImage(lines: [StackedLine],
                                          leadingGlyph: NSImage? = nil,
                                          appearance: NSAppearance? = nil) -> NSImage {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        paragraph.lineSpacing = 0
        paragraph.maximumLineHeight = 10.5
        paragraph.minimumLineHeight = 10.5
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        let attr = NSMutableAttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { attr.append(NSAttributedString(string: "\n")) }
            attr.append(barLine(line.text, severity: line.severity, font: font, paragraph: paragraph, appearance: appearance))
        }
        let textSize = attr.size()
        let height = NSStatusBar.system.thickness
        let glyphW = leadingGlyph?.size.width ?? 0
        let gap: CGFloat = leadingGlyph == nil ? 0 : 4
        let textW = ceil(textSize.width)
        let width = max(1, glyphW + gap + textW + 2)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        if let glyph = leadingGlyph {
            let gy = ((height - glyph.size.height) / 2).rounded()
            glyph.draw(at: NSPoint(x: 0, y: gy), from: .zero, operation: .sourceOver, fraction: 1)
        }
        // 1pt 下にずらす。各行のボックスは下端に空のディセンダ領域を抱えているため、幾何学的な
        // 中央に置くとグリフの塊がやや上に見える。目視で確認済み。
        let y = ((height - textSize.height) / 2).rounded() - 1
        attr.draw(in: NSRect(x: glyphW + gap, y: y, width: textW, height: ceil(textSize.height)))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

}
