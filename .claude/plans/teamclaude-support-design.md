# teamclaude 対応 詳細設計

対象リポジトリ: claude-usage-bar
作成日: 2026-09-09
状態: 実装未着手。この文書は実装エージェントへの指示書であり、設計判断をやり直さずに済む粒度で書いている

## 1. ゴールと非ゴール

ゴール

1. teamclaude が管理するプール全アカウントの 5h / Week(all) / Week(Fable) の残量を、メニューバーとポップオーバーに表示する
2. 非 teamclaude 環境でも従来どおり動く。情報源は設定ウィンドウの明示的な選択で切り替える。自動フォールバックはしない
3. teamclaude の版が上がってレスポンスが増えても壊れない

非ゴール

1. **プールで今アクティブなアカウントを示すこと。** teamclaude はローテーションするので「今アクティブ」は数秒で変わり、メニューバーに出す価値が無い。情報源に teamclaude を選んだ時点でアクティブという概念を持ち込まない。したがって `currentAccount`、`sessions`、`probe` は一切読まない
2. teamclaude への書き込み操作。`POST /teamclaude/reload` と `/teamclaude/switch` は呼ばない
3. プール全体の重み付き集計の表示
4. teamclaude のアカウントと `~/.claude*` 設定ディレクトリの対応付け。両者が一致する保証はスキーマに無い

## 2. 実測で確定した前提

稼働中の teamclaude は v1.1.17 である。以下はすべて実測で確認済みの事実であり、設計の前提として扱ってよい。

### 2.1 使用するエンドポイント

```
GET http://127.0.0.1:<port>/teamclaude/quota
```

loopback からの無認証 GET が 200 を返す。これは公式ドキュメント `docs/usage.md` に意図された動作として記述されており、裏技ではない。今後 `proxy.trustLoopback: false` や転送ヘッダ付きの場合に免除されない条件が入るが、127.0.0.1 を直接叩く限り影響しない。

レスポンスの構造。

```
{
  "accounts": [
    { "name": "<email>", "type": "oauth", "disabled": false, "status": "active",
      "tier": { "rateLimitTier": "...", "seatTier": "...", "weight": 5 },
      "buckets": {
        "fiveHour":     { "utilization": 0.48, "remaining": 0.52, "resetAt": <ms epoch>, "source": "unified5h" },
        "weeklyShared": { "utilization": 0.39, "remaining": 0.61, "resetAt": <ms epoch>, "source": "unified7d" },
        "weeklySonnet": { "utilization": 0.39, "remaining": 0.61, "resetAt": <ms epoch>, "source": "unified7d" },
        "weeklyFable":  { "utilization": 0.28, "remaining": 0.72, "resetAt": <ms epoch>, "source": "unified7dFable" }
      } }
  ],
  "aggregate": { "fiveHour": { "capacityWeight": 10, "usedWeight": 3.05, "remainingWeight": 6.95,
                               "utilization": 0.305, "remaining": 0.695, "knownAccounts": 2,
                               "nextResetAt": <ms epoch> }, ... },
  "unknownTiers": ..., "warmup": ...
}
```

確定事項

- `utilization` と `remaining` は 0〜1 の比率。`resetAt` は ms epoch
- `weeklySonnet` の `source` が `unified7d` になっている。Sonnet 固有の値が未観測のとき共通週次で埋めている
- JSON のキーは既に camelCase である
- レスポンスサイズは約 2.9KB
- このエンドポイントは v1.1.17 で新設された。**v1.1.16 以前では 404 になる**
- トークン、API キーの類は含まれない。ただしメールアドレスは含まれる

### 2.2 安定性の約束が無いこと

`/teamclaude/quota` にも `/teamclaude/status` にも、安定性やバージョニングの約束は無い。公式ドキュメントに API リファレンスページが無く、CHANGELOG も無い。フィールドは機能追加のたびに増える運用である。

これが 6 節で防御的な読み方をする根拠である。仕様が文書化されていない以上、こちらが観測した形を仕様と見なすしかなく、その形が予告なく変わることを前提に置く。

### 2.3 v1.1.14 から v1.1.17 への差分

差分は加算のみである。消えたキー、改名、型変更、意味変更はゼロであることを実測とコード読解の両方で独立に確認した。

- トップレベル追加: `defaultTarget`, `expiryRouting`, `usageDimensions`
- `accounts[]` 追加: `maxUsage`、null 許容。`pressure`
- `accounts[].quota` 追加: `backend`, `spend`
- `sessions` 追加: `starvedMax`
- `unifiedStatus` の語彙、`unified*` の 0〜1 スケール、`*Reset` の ms epoch はいずれも不変

この実績は「増える方向にしか変わらない」ことの証拠ではないが、未知キーを無視する読み方をしておけば少なくともこの種の変化では壊れないことを示している。

### 2.4 設定ファイルとポート

設定パスの解決順序は v1.1.14 から不変である。

1. `TEAMCLAUDE_CONFIG`
2. `$XDG_CONFIG_HOME/teamclaude.json`
3. `~/.config/teamclaude.json`

既定ポートは 3456 で、`proxy.port` で変更できる。このファイルには平文の OAuth アクセストークン、リフレッシュトークン、proxy の apiKey が入っている。

### 2.5 使わないと決めたもの

`~/.config/teamclaude.state.json` は読まない。v1.1.17 で atomic write に変わり読み取り中の破損レースは解消したが、採用しない理由は別にある。4.1 で述べる。

## 3. 情報源の抽象化

### 3.1 現状

`UsageService.snapshot()` は `ConfigDiscovery.discover()` を `UsageService.swift:24`、`KeychainReader.accessToken()` を `UsageService.swift:42`、`client.fetchWindows()` を `UsageService.swift:46` で直接呼んでいる。Core に protocol は 1 つも無く、DI されているのは具象 struct の `client: UsageAPIClient` だけである。

### 3.2 採用する構造

Core に protocol を 1 つだけ切る。

```
public protocol UsageSource: Sendable {
    func snapshot(now: Date) async -> UsageSnapshot
}
```

このシグネチャは既存の `UsageService.snapshot(now:)` そのものなので、境界を入れても呼び出し側の形は変わらない。

実装は 2 つ。

- `LocalConfigUsageSource`: 現在の `UsageService.snapshot()` の本体をそのまま移設したもの。`client: UsageAPIClient` を保持する
- `TeamclaudeUsageSource`: `/teamclaude/quota` を読むもの

`UsageService` は名前と役割を残し、中身を合成ルートに置き換える。

```
public struct UsageService: Sendable {
    private let source: any UsageSource

    public init(_ kind: UsageSourceKind = .local, client: UsageAPIClient = UsageAPIClient()) {
        switch kind {
        case .local: self.source = LocalConfigUsageSource(client: client)
        case .teamclaude: self.source = TeamclaudeUsageSource()
        }
    }

    public init(source: any UsageSource) { self.source = source }

    public func snapshot(now: Date = Date()) async -> UsageSnapshot {
        await source.snapshot(now: now)
    }
}
```

`init(source:)` はテスト用のスタブ注入口である。`StatusItemController.swift:142` の `UsageService()` は `UsageService(model.settings.usageSource)` の 1 行に変わる。

### 3.3 なぜ protocol にしたか

2 つの情報源は依存の集合がまったく違う。ローカル経路は FileManager と `/usr/bin/security` の外部実行と Anthropic への HTTPS、teamclaude 経路は loopback HTTP と設定ファイル 1 本である。境界を入れないと `UsageService.snapshot()` が互いに無関係な 2 つの半身を抱えた 1 つの巨大関数になり、テストの継ぎ目が無くなる。protocol はその継ぎ目そのものである。

却下した案を 10 節に記録する。

### 3.4 Core を AppKit 非依存・テスト可能に保つ方法

- ロジックの本体は純関数に切り出す。`TeamclaudeQuotaClient.mapQuota(_ data: Data, now: Date) throws -> [AccountUsage]` が JSON から `AccountUsage` を作る唯一の場所であり、ネットワーク無しで固定フィクスチャに対してテストできる。`UsageAPIClient.mapLimits` が `UsageAPIClient.swift:62` で internal static として切り出され `UsageParsingTests` からフィクスチャでテストされているのと同じ形である
- HTTP そのものは `TeamclaudeUsageSource` が持つ `transport: @Sendable (URL) async throws -> Data` クロージャに注入する。既定値は実物の URLSession 呼び出し。テストは固定 Data を返すスタブや throw するスタブを渡す。protocol を増やさず Sendable なクロージャで足りる
- 設定ファイルの読み取りは `TeamclaudeConfig.resolvePort(environment:homeDirectory:)` が `environment` と `homeDirectory` を引数で受ける。`ConfigDiscovery.discover(homeDirectory:)` が `ConfigDiscovery.swift:31` で同じ形を採っており、`UsageParsingTests` は一時ディレクトリを渡してテストしている。同じ手を使う

## 4. teamclaude 経路の実装方式

### 4.1 `/teamclaude/quota` 1 本で完結させる

判断: `GET /teamclaude/quota` だけを使う。`/teamclaude/status` も `state.json` も読まない。

`/teamclaude/status` を併用する理由が残っていないことを確認しておく。status にしか無い情報は `currentAccount`、`sessions`、`probe`、`unifiedStatus`、`switchThreshold` である。このうち表示に使う候補だったのは `currentAccount` だけであり、それは 1 節のとおり非ゴールになった。残りはいずれも表示しないと決めている。したがって 2 本目を叩く動機は無い。

quota 側の利点

1. バケットが `fiveHour` / `weeklyShared` / `weeklySonnet` / `weeklyFable` に整理済みで、`unified*` の名前を自前で仕分ける必要が無い
2. `resetAt` がバケットに同居しており、`unified5h` と `unified5hReset` のような対応付けを手で書かなくてよい
3. レスポンスが 2.9KB と軽い。status は 7KB
4. 読むエンドポイントが 1 本ならマッパーも 1 つで済む。安定性の約束が無い API に対して、腐り得る面を最小にできる

state.json を使わない理由

1. quota エンドポイントが持つバケット整形が state.json には無い。生の `unified*` から自前で仕分ける第 2 のマッパーが要る
2. マッパーが 2 つになると、2.2 で述べた「仕様が文書化されていない」性質の影響を 2 倍受ける
3. teamclaude が動いていないなら、プールという概念自体が現在の実態を表さない。60 秒前の残量を見せるより、到達できないという事実を見せるほうが正しい

ユーザーが求めた「設定で切り替え」は情報源そのものの選択、つまり teamclaude 経路と既存の config dir 経路の二択である。teamclaude 内部の読み口の二択をユーザーに見せる意図ではない。

### 4.2 リクエスト

```
GET http://127.0.0.1:<port>/teamclaude/quota
```

- ホストは `localhost` ではなく `127.0.0.1` のリテラルを使う。teamclaude が IPv4 のみに bind していた場合に `localhost` が `::1` に解決されて失敗するのを避けるため
- `x-api-key` は付けない。2.1 のとおり loopback は無認証で通る。API キーは `~/.config/teamclaude.json` にあるが、そこから読むのは `proxy.port` だけに限定する
- `URLSession.shared` を使わず専用のセッションを作る。`URLSessionConfiguration.ephemeral` に `timeoutIntervalForRequest = 2`、`requestCachePolicy = .reloadIgnoringLocalCacheData`、`connectionProxyDictionary = [:]` を設定する。teamclaude 自身が HTTP プロキシであるため、システムのプロキシ設定が teamclaude を指している環境で 127.0.0.1 宛のリクエストがプロキシを経由して回り込むのを確実に断つ。タイムアウトを 2 秒に切るのは、リフレッシュがメニューバーの更新を止めないようにするため
- ステータスコードが 200 以外なら失敗として扱う

### 4.3 ポート解決

`TeamclaudeConfig` を新設し、2.4 の順序でパスを決める。

1. 環境変数 `TEAMCLAUDE_CONFIG` が空でなければ、その値をファイルパスとして使う
2. 環境変数 `XDG_CONFIG_HOME` が空でなければ `$XDG_CONFIG_HOME/teamclaude.json`
3. それ以外は `<home>/.config/teamclaude.json`

そのファイルを次の型でだけデコードする。

```
struct Root: Decodable {
    struct Proxy: Decodable { let port: Int? }
    let proxy: Proxy?
}
```

`proxy.port` が 1...65535 に収まればそれを使う。ファイルが無い、読めない、JSON でない、`proxy.port` が無い、範囲外のいずれでも既定値 3456 にフォールバックする。

このファイルには平文の認証情報が入っている。したがって次を厳守する。

- デコード対象の型に `proxy.port` 以外のフィールドを一切定義しない
- デコードの失敗を握りつぶす。`DecodingError` の内容を print、`NSLog`、`os_log`、`sourceError` の文字列を含むどの出力経路にも流さない。失敗は黙って既定ポートへのフォールバックとして扱う。パースエラーの説明文にファイル内容の断片が含まれ得るためである
- ファイル内容を変数に保持し続けない。`resolvePort` の中で読んで捨てる

env 変数の扱いの限界: Finder やログイン項目から起動された GUI アプリはシェルの環境変数を継承しない。したがって実運用では 1 と 2 はほぼ効かず、3 の既定パスだけが使われる。`swift run` やターミナルからの起動では効く。この非対称を承知のうえで 1 と 2 も実装する。3 行で済み、ターミナル起動時には正しく動くからである。

### 4.4 バケットのマッピング

`buckets` の各エントリを `RateWindow` に写す。変換は `TeamclaudeQuotaClient.mapQuota` の中 1 か所だけで行う。

| バケット | RateWindowKind | label | scopeModel |
| --- | --- | --- | --- |
| `fiveHour` | `.session` | `Session (5h)` | nil |
| `weeklyShared` | `.weeklyAll` | `Week (all)` | nil |
| `weeklyFable` | `.weeklyScoped` | `Week (Fable)` | `Fable` |
| `weeklySonnet` | 出さない | | |

ラベル文字列は `UsageAPIClient.swift:101-103` のローカル経路と一字一句そろえる。同じ画面に両方の経路が出ることは無いが、ポップオーバーの見た目が情報源で変わる理由が無い。

`weeklySonnet` を出さない理由

1. 実測で `source` が `unified7dSonnet` ではなく `unified7d` になっている。Sonnet 固有の測定値ではなく、共通週次の値を流用した数字である。これを Week(Sonnet) として見せるのは嘘に近い
2. ポップオーバーは `PopoverView.swift:120` で session / weeklyAll / weeklyFable の 3 つ固定を描く。Sonnet ウィンドウを作っても画面には出ない。にもかかわらず `AccountUsage.mostConstrainedWindow` と `BarTitleFormatter.iconWindow` の候補には入るので、画面に理由の出ない色変化を生む
3. `weeklyShared` と同じ値なので、`mostConstrained` の判定で同じ数字が二重に候補に入る

将来 Sonnet を出すなら、ポップオーバーの行とバーの metric を同時に足す。ウィンドウだけ増やしてはならない。

### 4.5 値の変換

`usedPercent`

```
usedPercent = min(100, max(0, utilization * 100))
```

変換場所は `mapQuota` の中、`RateWindow` を組み立てる瞬間ただ 1 か所である。`UsageAPIClient.mapLimits` が `UsageAPIClient.swift:107-115` で API のペイロードを写すのと同じ位置づけで、境界の外に 0〜1 の値を漏らさない。

`RateWindow.usedPercent` が 0...100 であるという契約は絶対に維持する。`BarTitleFormatterTests` の期待値、`BarIcon.fraction = usedPercent / 100` を経由する `ClawdGlyph` のゲージ描画、`PopoverView.swift:153` の `UsageBar(fraction:)` がすべてこの範囲に依存している。

Fable は overage で 1 を超え得るので、上限のクランプが効く。100 に丸めることで超過量は失われるが、100% を超えた時点で深刻度は `.critical` に固定されており色も表示も変わらない。契約を緩めてゲージ描画とアイコンの fraction に波及させる価値は無い。

`remaining` は読まない。`RateWindow.remainingPercent` が `Models.swift:55` で `100 - usedPercent` として計算される唯一の場所であり、サーバー側の `remaining` と両方を持つと丸め差で食い違い得る。片方だけを真とする。

`resetsAt`

```
resetsAt = resetAt.map { Date(timeIntervalSince1970: $0 / 1000) }
```

`resetAt` が null、欠損、0 以下のいずれでも nil にする。ms epoch の 0 は 1970 年であり、リセット時刻として明らかに無効である。

`severity`

常に nil にする。`/teamclaude/quota` には `unifiedStatus` に相当するフィールドが無い。深刻度は `BarTitleFormatter.windowSeverity` の閾値判定だけで決まる。

これは横断的不変条件にとって良い結果である。`windowSeverity` は `BarTitleFormatter.swift:209-213` のまま 1 行も変えずに済み、深刻度判定が 1 か所に集約されている性質が完全に保たれる。

`isActive`

常に false にする。`RateWindow.isActive` は `Models.swift:31` のとおり「そのアカウント内でどのウィンドウがレート制限を効かせているか」を表すサーバー由来のフラグであり、quota エンドポイントには対応する情報が無い。false は「そういう指定が来ていない」ことを正しく表す。

この結果、teamclaude 経路では `AccountUsage.mostConstrainedWindow` が `Models.swift:95-96` の後段、つまり使用率が最も高いウィンドウを返す枝だけを通る。`barMetric` が `.mostConstrained` のときも意味のある値になるので、対応は不要である。

### 4.6 アカウントの扱い

- `name` をそのまま `AccountUsage.email` に入れる。加工しない。`email` は `Models.swift:71` で `Identifiable.id` になっており、teamclaude が同一メール複数組織を区別するために付ける `(Org)` 形式を剥がすと `ForEach` の id が重複して SwiftUI の描画が壊れる
- `name` が null または空のアカウントはスキップする。id が作れないためである
- `disabled` が true のアカウントは結果に含めない。ユーザーが明示的にプールから外したアカウントであり、プールの残量として数える対象ではない。実測で Bool の `false` を確認しているので型の仮定が要らない
- `folders` は常に `[]` にする。`folders` は `Models.swift:65` のとおり「この認証情報を共有する設定フォルダの短縮名」であり、config dir が対応しないアカウントがあり得る teamclaude 経路では埋めるべき値が無い。`[]` にすると `BarTitleFormatter.accountLabel` が `BarTitleFormatter.swift:153-156` で email のローカル部にフォールバックし、ポップオーバーはフォルダ行を出さない。どちらも意図した結果である
- `error` は常に nil にする。アカウント単位の失敗という概念が quota エンドポイントに無い。失敗はレスポンス全体の失敗としてしか起きない
- `fetchedAt` は `now` を入れる
- 並び順は teamclaude が返した配列順を保つ。ローカル経路が `UsageService.swift:67` でフォルダ名でソートしているのと違うが、プールの順序はプール側が持つ意味なので並べ替えない

`status` と `tier` は読まない。`status` は実測値が `"active"` の 1 つしかなく語彙が分からない。値が入ったときの型と意味を確認できていないフィールドを表示に結線すると、検証できない分岐が残る。`tier` は重み付き集計のための情報で、集計を表示しない以上使い道が無い。

`aggregate`、`unknownTiers`、`warmup` は読まない。理由は 10 節に記録する。

### 4.7 teamclaude が停止している / 版が古い / 未インストールのとき

`TeamclaudeUsageSource.snapshot(now:)` は例外を投げない。既存の `UsageService.snapshot()` が「例外を投げず失敗は値に落とす」契約であり、これを維持する。

失敗時は `UsageSnapshot(accounts: [], generatedAt: now, sourceError: <短い説明>)` を返す。`sourceError` はポップオーバーにそのまま出るので短くする。

| 失敗 | sourceError |
| --- | --- |
| 接続失敗、タイムアウト | `teamclaude not reachable on port 3456` |
| HTTP 404 | `teamclaude 1.1.17 or newer required` |
| その他の非 200 | `teamclaude HTTP 503` |
| デコード失敗、`accounts` キー欠損 | `teamclaude: bad response` |

404 を専用のメッセージにするのは、`/teamclaude/quota` が v1.1.17 で新設されたエンドポイントであり、404 の原因がほぼ確実に版の古さだからである。「到達できない」と一括りにすると、teamclaude は動いているのに理由が分からない状態になる。

404 のときに `/teamclaude/status` へフォールバックすることはしない。理由は 10 節に記録する。

BarSeverity へのマップは 2 通りに分ける。

- 直近の値を引き継げた場合、つまり `sourceError != nil` かつ引き継ぎ後の `accounts` が空でない場合: バーの色は引き継いだデータ本来の深刻度のままにする。`.stale` に落とさない。`.stale` は `BarTitleFormatter.swift:220-227` の `rank` で `.warning` より下位なので、critical のデータを引き継いだのに色が灰色になると危険側に倒れる。メニューバーは有用なまま残し、事情はポップオーバーのバナーで説明する
- 引き継ぐ値が無い場合、つまり `accounts` が空の場合: `.error` にする。teamclaude 未インストール、版が古い、初回起動直後の到達失敗がここに当たる。赤い Clawd とゲージ無しになり、ポップオーバーに `sourceError` が出る

`.stale` は「まだ一度もデータが無い」という既存の意味のまま据え置く。`UsageSnapshot.empty` は `sourceError` が nil なので従来どおり `.stale` である。

## 5. 型の変更

要件から「アクティブなアカウントを示す」が外れたことで、型の変更は 1 つだけになった。

### 5.1 UsageSnapshot に sourceError を足す

```
public var sourceError: String?
```

`init` の末尾に `sourceError: String? = nil` を追加する。`UsageSnapshot(accounts:generatedAt:)` を使っている既存のテストはそのままコンパイルされる。Codable は synthesized のままでよい。Optional のキーは JSON に無ければ nil としてデコードされる。

`retainingWindows(from:)` を `Models.swift:117-128` で拡張する。先頭に丸ごと引き継ぎの分岐を足す。

```
if sourceError != nil, accounts.isEmpty, !previous.accounts.isEmpty {
    return UsageSnapshot(accounts: previous.accounts,
                         generatedAt: previous.generatedAt,
                         sourceError: sourceError)
}
```

`generatedAt` に `previous.generatedAt` を入れるのが要点である。ポップオーバーのフッターは `PopoverView.swift:53` で `Updated \(generatedAt)` を描くので、ここに now を入れると古いデータに新しい時刻が付いた嘘になる。前回の時刻を残せば「Updated 12:03」とバナーが並んで整合する。

既存のアカウント単位の引き継ぎの枝は変更しない。

### 5.2 変更しない型

- **`AccountUsage`** — フィールドを増やさない。「プールでアクティブか」は非ゴールになった
- **`RateWindow`** — フィールドも computed property も増やさない。`isActive` は既存のまま触らない。4.5 のとおり teamclaude 経路では常に false を入れる
- **`RateWindowKind`** — 増やさない。`weeklySonnet` を出さないため
- **`BarSeverity`** — 増やさない。`.error` と `.stale` の既存の 2 つで足りる
- **`BarTitleFormatter.windowSeverity`** — 1 行も変えない。quota エンドポイントに `unifiedStatus` 相当が無く、深刻度は閾値判定だけで決まる。深刻度判定が 1 か所に集約されているという横断的不変条件が完全に保たれる
- **`BarTitleFormatter.iconWindow`** — 変えない。候補は barMetric のウィンドウに加えて常に 5h と Week(all) という規則のままでよい。teamclaude 経路でもこの 3 種類しか作らない
- **`AccountBarMode`** — case を増やさない。teamclaude 選択中の `.active` の扱いは 7.3 のとおり読み替えで解く

### 5.3 BarTitleFormatter の変更

`sourceError` を見る 2 か所だけを直す。深刻度の閾値判定とアイコンのウィンドウ選択には触らない。

`make(from:settings:now:)` の `BarTitleFormatter.swift:26-28`

```
guard let account = selectedAccount(from: snapshot, settings: settings) else {
    return BarTitle(text: "", severity: snapshot.sourceError == nil ? .stale : .error)
}
```

`icon(from:settings:)` の `BarTitleFormatter.swift:74`

```
guard !icons.isEmpty else {
    return BarIcon(severity: snapshot.sourceError == nil ? .stale : .error, fraction: nil)
}
```

`icon(for account:settings:)` は変更しない。アカウント単位の関数であり `sourceError` を知る必要が無い。

## 6. 版差に対する耐性

2.2 のとおり、このエンドポイントには安定性やバージョニングの約束が無い。API リファレンスページも CHANGELOG も存在せず、フィールドは機能追加のたびに増える運用である。文書化された仕様が無い以上、こちらが観測した形を仕様と見なすしかなく、その形が予告なく変わる前提で読む。

方針は 1 つである。teamclaude の版番号で分岐しない。レスポンスの形だけを見て判断し、形が想定と違えば嘘の数字を出さずに `.error` か `.stale` に倒れる。

### 6.1 未知のキーが増えても decode を失敗させない

Swift の synthesized `Decodable` は、型に定義されていないキーを黙って無視する。したがってキーの追加は無害であり、追加の対策は要らない。2.3 の差分がすべて加算だったことは、この性質だけで v1.1.14 から v1.1.17 の変化を吸収できることを意味する。

decode が失敗するのは次の 2 つだけである。

1. 型に非 optional で定義したフィールドが JSON から消えたとき
2. 定義した型と実際の値の型が食い違ったとき

対策は 2 段構えである。

**第 1 に、読まないキーを型に定義しない。** `maxUsage`、`pressure`、`backend`、`spend`、`tier`、`status`、`aggregate`、`unknownTiers`、`warmup`、`defaultTarget`、`expiryRouting`、`usageDimensions` はいずれも型に書かない。定義しないキーは型不一致を起こしようがないので、防御としても最も強い。4.6 でこれらを読まないと決めたのは、この観点からも正しい。

**第 2 に、定義するフィールドを例外なくすべて optional にする。**

```
struct Root: Decodable {
    let accounts: [Failable<Account>]?
}

struct Account: Decodable {
    let name: String?
    let disabled: Bool?
    let buckets: Buckets?
}

struct Buckets: Decodable {
    let fiveHour: Bucket?
    let weeklyShared: Bucket?
    let weeklyFable: Bucket?
}

struct Bucket: Decodable {
    let utilization: Double?
    let resetAt: Double?
}
```

`weeklySonnet` は 4.4 で出さないと決めたので型に定義しない。`remaining` と `source` も 4.5 のとおり読まないので定義しない。

`keyDecodingStrategy` は設定しない。teamclaude のキーは既に camelCase である。`UsageAPIClient.mapLimits` が `UsageAPIClient.swift:80` で使っている `.convertFromSnakeCase` をこちらのデコーダに付けてはならない。付けると全キーが取れなくなる。

**第 3 に、`accounts` の要素を `Failable<Account>` で包む。**

```
struct Failable<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
```

`init(from:)` が決して throw しないので、1 つのアカウントで型不一致が起きても他のアカウントは読める。10 行に満たないコストで、「1 アカウントに新しい型のフィールドが入った瞬間にバーが全滅する」という失敗モードを消せる。

ただし黙って半分だけ見せてはならない。`mapQuota` は decode に失敗した要素を数え、1 件以上なら呼び出し側に伝える。`mapQuota` の戻り値を次の形にする。

```
struct QuotaResult { let accounts: [AccountUsage]; let unreadable: Int }
```

`TeamclaudeUsageSource` は `unreadable > 0` のとき `sourceError = "teamclaude: 1 account unreadable"` を立てる。4.7 の規則にそのまま乗るので、accounts が空でなければバーは読めたデータの色を保ち、ポップオーバーにバナーが出る。

### 6.2 期待するキーが欠損したときのフォールバック

「値が無い」と「値が 0」を混同しないことが要点である。

| 状況 | 挙動 | 表示 |
| --- | --- | --- |
| `buckets.fiveHour` が欠損、または `utilization` が null | `RateWindow` を作らない | `5h ?%`、バーは `.stale` の灰色 |
| `utilization` が `0` | 0% の `RateWindow` を作る | `5h 0%`、緑 |
| `resetAt` が null、欠損、0 以下 | `resetsAt = nil` | リセット表示を省略。`DateFormatting` が空文字を返す |
| `buckets` オブジェクトごと欠損 | ウィンドウ 0 件 | カードに `No usage data yet`、バーは `.stale` |
| `name` が null または欠損 | そのアカウントをスキップ | 一覧に出ない |
| `disabled` が欠損 | 除外しない | 全アカウントを表示する。安全側 |
| `accounts` が `[]` | 空のスナップショット、`sourceError` は nil | 空状態のメッセージ |
| `accounts` キーごと欠損 | throw して `sourceError` | 赤い Clawd とバナー |

未観測のバケットを 0% として作ってはならない。0% は「使っていない」という嘘になる。ウィンドウを作らなければ `BarTitleFormatter.valueFragment` が `BarTitleFormatter.swift:167-169` で `?` を出し、`severity(account:window:)` が `BarTitleFormatter.swift:197-201` で `.stale` を返す。どちらも既存の実装で足りる。

### 6.3 版の検出

判断: **版番号を読まない。読めたとしても分岐に使わない。**

理由

1. 版で分岐すると、実機で確認していない版ごとに未検証のコードパスが増える。分岐が増えるほど「どの版でどう動くか」が誰にも分からなくなる
2. 版が同じでもビルドが違えばスキーマが違い得る。2.2 のとおり CHANGELOG も API リファレンスも無く、版番号は形の保証にならない
3. 6.1 と 6.2 の構造駆動の読み方があれば、版を知る必要が無い。形が想定どおりなら読み、違えば倒れる

唯一の例外が 4.7 の 404 メッセージである。これは版で分岐しているのではなく、「このエンドポイントが存在しない」という観測結果に対して、原因として最も可能性の高い説明を文言に添えているだけである。分岐する挙動は他の非 200 とまったく同じである。

版に依存しない読み方の担保は 3 つの層で行う。

1. 読まないキーを型に書かない。全 optional。要素単位の failable decode
2. `accounts` キーの存在という最小限の構造チェック
3. `mapQuota` のフィクスチャテスト。v1.1.17 の形を固定し、将来スキーマを追ったときに「何を前提にしていたか」を示す唯一の記録になる。フィクスチャの直前に採取元の版をコメントで書く

### 6.4 想定と違うときに嘘を出さないこと

`mapQuota` は decode 後に構造的な健全性チェックを 1 つだけ行う。**`accounts` キーが存在しない、つまり decode 結果が nil のときに throw する。**

`accounts` が空配列 `[]` のときは throw しない。teamclaude が起動していてプールにアカウントが 0 件という正当な状態と区別できるからである。この場合は `accounts` が空で `sourceError` も nil のスナップショットになり、バーは `.stale`、ポップオーバーは空状態のメッセージを出す。

これ以上のチェックは足さない。「name を持つアカウントが 1 件以上あること」のような追加条件は、正当な状態を誤って異常と判定する側の誤りを増やす。

嘘の数字を出さないことの根拠を経路ごとに整理する。

| スキーマ破損の形 | 到達する状態 | 嘘の数字が出るか |
| --- | --- | --- |
| エンドポイントが消えた、パスが変わった | HTTP 404 → `sourceError` | 出ない。`.error` |
| 版が古くて `/quota` が無い | HTTP 404 → 版を示す `sourceError` | 出ない。`.error` |
| レスポンスが JSON でなくなった | decode 失敗 → `sourceError` | 出ない。`.error` |
| `accounts` が改名された | nil → throw → `sourceError` | 出ない。`.error` |
| `buckets` が改名された | ウィンドウ 0 件 | 出ない。`.stale` と `No usage data yet` |
| `fiveHour` が改名された | そのウィンドウだけ欠落 | 出ない。`5h ?%` |
| `utilization` が文字列になった | 該当アカウントの decode 失敗 → 部分表示 + `sourceError` | 出ない |
| バケットの入れ子が 1 段変わった | `buckets` が nil 扱い → ウィンドウ 0 件 | 出ない。`.stale` |
| **`utilization` の単位が 0〜1 から 0〜100 に変わった** | **クランプされて全件 100%** | **出る** |

唯一防げないのは単位の変更である。0〜1 と 0〜100 は同じ Double であり、値だけを見て判別できない。0.43 は 0〜100 系では 0.43% として妥当な値でもある。

これは受け入れたリスクとする。緩和として、`mapQuota` は比率が 1 を超えてもクランプするだけで throw しない。単位が変わった場合の見え方は「全アカウントが常に 100% critical」という、誰が見ても異常と分かる表示になる。中途半端に正しく見える表示より発見が早い。単位変更を自動検出する仕掛けは作らない。

`remaining` と突き合わせて `utilization + remaining == 1` を検証すれば単位変更を検出できるが、4.5 で `remaining` を読まないと決めている。検出のためだけに 2 つ目の真実を持ち込むと、丸め差で偽陽性を出す新しい失敗モードが増える。採らない。

## 7. 設定の追加

### 7.1 情報源の選択を DisplaySettings に入れない

新しい enum を Core に置く。

```
public enum UsageSourceKind: String, Sendable, CaseIterable, Codable {
    case local
    case teamclaude
}
```

`DisplaySettings` には入れない。`DisplaySettings` は `DisplaySettings.swift:56-57` のコメントどおり「バータイトルを決めるための設定項目」であり、`BarTitleFormatter` に渡る整形の契約である。どこからデータを取ってくるかは整形に関係が無い。ここに入れると `BarTitleFormatter` のテストが情報源の概念を知ることになり、契約が濁る。

App 側の `showBarIcon` と `refreshInterval` が既に「`DisplaySettings` に無く `SettingsStore` だけが持つ設定」の前例になっている。`SettingsStore.swift:54` と `:70` を参照。

### 7.2 SettingsStore への追加

```
private enum Key {
    ...
    static let usageSource = "usageSource"
}

@Published var usageSource: UsageSourceKind {
    didSet { defaults.set(usageSource.rawValue, forKey: Key.usageSource) }
}
```

`init` での読み出しは既存の enum 項目と同じ形にする。

```
self.usageSource = (defaults.string(forKey: Key.usageSource)
    .flatMap(UsageSourceKind.init(rawValue:))) ?? .local
```

既定値は `.local` である。既存ユーザーの挙動は一切変わらない。UserDefaults にキーが無い状態がそのまま `.local` を意味するので、マイグレーションのコードは要らない。

初回起動時に teamclaude を自動検出して既定を切り替えることはしない。ユーザーが「自動フォールバックではなく明示的な選択肢」を要件として指定しているためである。

### 7.3 accountMode の読み替え

teamclaude を情報源に選んでいる間は `.active`、つまり「最も制約の厳しいアカウント 1 件」を使わせない。プールはローテーションするので、1 件だけを映す表示に意味が薄い。

実装は **永続値を書き換えず、読み出し時に読み替える**。

```
var effectiveAccountMode: AccountBarMode {
    if usageSource == .teamclaude, accountMode == .active { return .all }
    return accountMode
}
```

`displaySettings` computed property の `SettingsStore.swift:123` を `accountMode: effectiveAccountMode` に差し替える。`@Published var accountMode` の永続化はそのまま残す。

永続値を書き換えない理由: ユーザーが `.local` で `.active` を選んでいた状態は、teamclaude に切り替えている間だけ `.all` として振る舞い、`.local` に戻すと `.active` に戻る。書き換えてしまうと元に戻す手段が失われる。設定を戻したときに元に戻ることが望ましいという要件を満たす。

`.pinned` はそのまま残す。プールの中の特定アカウントを見張りたいという要求は teamclaude でも成立する。

`.all` が teamclaude 選択時の実質的な既定になる。`DisplaySettings.default.accountMode` も `SettingsStore` の初期値も `.active` なので、新規ユーザーが teamclaude を選ぶと読み替えによって自動的に `.all` になる。既定値のための別処理は要らない。

`BarTitleFormatter.selectedAccount` の `switch` は `BarTitleFormatter.swift:50-59` のまま変更しない。case を増やさないので網羅性も壊れない。

### 7.4 SettingsView への追加

`General` セクションの直後に新しいセクションを 1 つ置く。

```
Section("Usage Source") {
    Picker("Source", selection: $settings.usageSource) {
        Text("Claude Code config folders").tag(UsageSourceKind.local)
        Text("teamclaude pool").tag(UsageSourceKind.teamclaude)
    }
    Text(sourceCaption)
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

`sourceCaption` は選択に応じて変える。

- `.local`: `Reads ~/.claude* config folders and the login keychain.`
- `.teamclaude`: `Reads http://127.0.0.1:<port>/teamclaude/quota. Needs teamclaude 1.1.17 or newer, running.` ポート番号は `TeamclaudeConfig.resolvePort()` の結果を埋め込む

teamclaude が未インストールの環境でも、情報源の選択肢は常に両方見せる。無効化も非表示にもしない。

1. 選択肢を隠すと、後から teamclaude を入れたユーザーが機能の存在に気づけない
2. 検出の判定を設定画面に置くと、設定画面を開いた瞬間に loopback へリクエストを飛ばす非同期処理が増える。設定画面は現在まったく非同期処理を持たない
3. 選んだのに何も出ない状態にはならない。ポップオーバーに `sourceError` のバナーが出て理由が読める

`Accounts` セクションの `Account` ピッカーは、teamclaude 選択中に `.active` の行を **出さない**。

```
Picker("Account", selection: $settings.accountMode) {
    if settings.usageSource == .local {
        Text("Active (most constrained)").tag(AccountBarMode.active)
    }
    Text("Pinned account").tag(AccountBarMode.pinned)
    Text("All accounts").tag(AccountBarMode.all)
}
if settings.usageSource == .teamclaude {
    Text("The pool rotates accounts, so a single most-constrained account is not shown. All accounts is used instead.")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

行を残して `.disabled(true)` を付ける案を採らない理由: SwiftUI の `Picker` は既定の `.menu` スタイルで、内側の行に付けた `.disabled` が視覚的にも操作的にも効かない場合がある。選べてしまう無効行を置くより、行を消して理由をキャプションで書くほうが確実で誤解が無い。

`.local` のときのラベルは `Active (most constrained)` のまま変えない。teamclaude 経路にアクティブという概念を持ち込まないと決めた以上、`.local` 側のラベルを変える理由が無い。

### 7.5 StatusItemController の変更

2 か所を直す。

**情報源の切り替えを検知して即座に再取得する。**

`StatusItemController.swift:44-49` の sink は現在 `updateBar()` と `scheduleTimer()` しか呼ばない。情報源を変えても次のタイマー発火まで古い情報源のデータが残り、最大 15 分間まちがった内容を表示する。

コントローラに `private var currentSource: UsageSourceKind` を持たせ、sink で比較する。

```
settingsCancellable = model.settings.objectWillChange
    .receive(on: RunLoop.main)
    .sink { [weak self] in
        guard let self else { return }
        if self.model.settings.usageSource != self.currentSource {
            self.currentSource = self.model.settings.usageSource
            self.model.snapshot = .empty
            self.refresh()
        }
        self.updateBar()
        self.scheduleTimer()
    }
```

`model.snapshot = .empty` で消すのが重要である。ローカル経路とプール経路ではアカウントの集合が違う。消さずに再取得すると `retainingWindows(from:)` が email をキーに前の情報源のアカウントを引き継ぎ、2 つの情報源のアカウントが混ざったスナップショットになる。

この sink が新しい値を読めるのは `.receive(on: RunLoop.main)` のホップがあるからである。`objectWillChange` はプロパティが変更される **前** に発火するので、ホップが無ければ古い値を読む。このホップを不要な遅延と見て削ってはならない。

**実行中のリフレッシュが別の情報源の結果を書き込まないようにする。**

`StatusItemController.swift:137-149` の `refresh()` は `guard !isRefreshing` で多重実行を防いでいる。情報源の切り替えが実行中のリフレッシュと重なると、上の sink が呼ぶ `refresh()` がこの guard で落とされ、その後に古い情報源の結果が `model.snapshot` に書き込まれる。クリアした意味が消える。

開始時に情報源を捕まえ、完了時に照合する。

```
private func refresh() {
    guard !isRefreshing else { return }
    let source = model.settings.usageSource
    isRefreshing = true
    model.isRefreshing = true
    Task { @MainActor in
        let fresh = await UsageService(source).snapshot()
        isRefreshing = false
        model.isRefreshing = false
        guard source == model.settings.usageSource else { return }
        model.snapshot = fresh.retainingWindows(from: model.snapshot)
        updateBar()
    }
}
```

`isRefreshing` の解除を guard より前に置くのが要点である。後ろに置くと、情報源が切り替わったときにフラグが立ったまま戻らず、以後リフレッシュが二度と走らなくなる。

### 7.6 PopoverView の変更

3 か所を足す。

1. **情報源のエラーバナー。** `model.snapshot.sourceError` が非 nil なら、アカウント一覧の上に 1 行出す。`exclamationmark.triangle.fill` と文字列を `SeverityColor.color(.error)` で描く。`PopoverView.swift:12` の分岐より前に置き、アカウントがあってもなくても出す
2. **空状態の文言。** `PopoverView.swift:33` の `No Claude Code accounts found` はローカル経路の言い回しなので、情報源に依存しない `No accounts found` に変える。`sourceError` が非 nil のときはバナーが理由を語るので、空状態のブロック自体を出さない
3. **データが無いアカウント。** `PopoverView.swift:99-111` の分岐に、`!account.hasError && windows.isEmpty` のとき `No usage data yet` を `SeverityColor.color(.stale)` で描く枝を足す

アクティブ表示のカプセルは作らない。非ゴールである。

### 7.7 承知したうえで直さないこと

1. **pinnedEmail が情報源をまたぐと外れる。** ローカル経路で `user@example.com` を pin したまま teamclaude 経路に切り替えると、teamclaude 側の名前が `user@example.com (Org)` の形のときに一致しない。`BarTitleFormatter.swift:52-56` のフォールバックが働いて most constrained になる。バーは動き続けるので実害は小さい
2. **設定ウィンドウの pin ピッカーの一覧が古い。** `SettingsView` は `StatusItemController.swift:103` で開いた時点の `model.snapshot.accounts` を受け取る。開いたまま情報源を切り替えると、ピッカーには前の情報源のアカウントが並ぶ。ウィンドウを開き直せば直る。情報源対応で新たに生じる制約ではなく既存の作りであり、今回は触らない
3. **アカウント単位の引き継ぎの観測時刻。** `Models.swift:127` は `generatedAt` に now を入れており、古いデータに新しい時刻が付く既存の不整合がある。今回追加する丸ごと引き継ぎだけは `previous.generatedAt` を保つが、既存の枝は変えない

## 8. テスト計画

すべて swift-testing で `Tests/ClaudeUsageBarCoreTests/` に置く。実行は `./Scripts/test.sh` である。素の `swift test` は使えない。

### 8.1 フィクスチャの置き方と匿名化

フィクスチャは Swift の文字列リテラルとしてテストファイルに直接書く。`UsageParsingTests.swift:9-36` が同じ形を採っており、`Package.swift` に resources 宣言を足さずに済む。`Package.swift` は今回いっさい変更しない。

`/teamclaude/quota` のレスポンスにトークンも API キーも含まれないことは実測で確認済みである。**ただしメールアドレスは含まれる。** 実在の値をリポジトリに置かない。

- メールアドレスは `a@example.com`、`b@example.com` を使う
- 組織名が要るケースは `Example Org` を使い、同一メール複数組織は `a@example.com (Example Org)` の形にする
- フィクスチャの直前に、採取元が teamclaude v1.1.17 であることを 1 行のコメントで書く。6.3 のとおり、これがスキーマの前提を示す唯一の記録になる

### 8.2 新規ファイル TeamclaudeQuotaTests.swift

`TeamclaudeQuotaClient.mapQuota` をフィクスチャに対して検証する。ネットワークもファイルも使わない。

1. `mapQuotaBuildsThreeWindows` — `fiveHour` 0.48 / `weeklyShared` 0.39 / `weeklyFable` 0.28 が `usedPercent` 48 / 39 / 28 になること。ラベルが `Session (5h)` / `Week (all)` / `Week (Fable)` であること。Fable の `scopeModel` が `"Fable"` であること
2. `mapQuotaDropsWeeklySonnet` — `weeklySonnet` を含むフィクスチャでウィンドウが 3 件のままであること
3. `mapQuotaClampsOverage` — `weeklyFable` の `utilization` が 1.15 のとき 100 になること
4. `mapQuotaSkipsMissingBuckets` — `fiveHour` を欠いたフィクスチャでセッションウィンドウが作られず 2 件になること。0% のウィンドウが作られないこと
5. `mapQuotaKeepsExplicitZero` — `utilization: 0` が 0% のウィンドウとして作られること。4 との対で「値が無い」と「値が 0」の区別を固定する
6. `mapQuotaSkipsNullUtilization` — `utilization: null` でウィンドウが作られないこと
7. `mapQuotaParsesMsEpochResetAt` — `resetAt: 1788945600000` が `Date(timeIntervalSince1970: 1788945600)` になること。`resetAt: null` と `resetAt: 0` で `resetsAt` が nil になること
8. `mapQuotaIgnoresRemaining` — `remaining` がわざと矛盾した値のフィクスチャで、`remainingPercent` が `100 - usedPercent` になること
9. `mapQuotaDropsDisabledAccounts` — `disabled: true` のアカウントが結果に含まれないこと
10. `mapQuotaSkipsAccountsWithoutName` — `name` が欠損したアカウントが結果に含まれないこと
11. `mapQuotaFoldersAreEmptyAndNoError` — 全アカウントの `folders` が `[]`、`error` が nil、`isActive` が全ウィンドウで false、`severity` が全ウィンドウで nil であること
12. `mapQuotaPreservesAccountOrder` — teamclaude が返した配列順が保たれること
13. `mapQuotaIgnoresUnknownKeys` — `tier` / `status` / `aggregate` / `warmup` および未知のキーを混ぜたフィクスチャが正常に読めること。6.1 の回帰テスト
14. `mapQuotaSurvivesOneMalformedAccount` — 2 件のうち 1 件の `utilization` を文字列にしたフィクスチャで、健全な 1 件が読め、`unreadable` が 1 になること。6.1 の要素単位 failable decode の回帰テスト
15. `mapQuotaThrowsWhenAccountsKeyMissing` — `accounts` キーの無い JSON で throw すること
16. `mapQuotaAcceptsEmptyAccountsArray` — `"accounts": []` で throw せず、空の結果で `unreadable` が 0 になること
17. `mapQuotaThrowsDecodingOnGarbage` — JSON でない入力で throw すること

### 8.3 新規ファイル TeamclaudePortTests.swift

`TeamclaudeConfig.resolvePort(environment:homeDirectory:)` を一時ディレクトリに対して検証する。`UsageParsingTests.swift:80-99` が一時ホームを組み立てる形をそのまま踏襲する。

書き込むファイルの中身は `{"proxy":{"port":39999}}` だけにする。トークンらしき文字列をテストに一切書かない。

1. `resolvePortReadsProxyPort` — `<home>/.config/teamclaude.json` の `proxy.port` を読むこと
2. `resolvePortFallsBackWhenFileMissing` — ファイルが無ければ 3456 になること
3. `resolvePortFallsBackOnMalformedJSON` — JSON でない内容で 3456 になること。例外が外に出ないこと
4. `resolvePortFallsBackWhenPortMissing` — `{"proxy":{}}` で 3456 になること
5. `resolvePortRejectsOutOfRange` — `0` と `70000` で 3456 になること
6. `resolvePortHonorsXDGConfigHome` — `XDG_CONFIG_HOME` を渡したとき、そのディレクトリ直下の `teamclaude.json` を読むこと
7. `resolvePortHonorsTeamclaudeConfig` — `TEAMCLAUDE_CONFIG` を渡したとき、そのパスのファイルを読むこと。`XDG_CONFIG_HOME` より優先されること

### 8.4 新規ファイル TeamclaudeSourceTests.swift

`TeamclaudeUsageSource` を注入したスタブ transport で検証する。

1. `sourceMapsSnapshotFromTransport` — 固定 Data を返すスタブで、アカウントが読め `sourceError` が nil になること
2. `sourceReportsSourceErrorOnTransportFailure` — throw するスタブで、`accounts` が空になり `sourceError` が非 nil になり、例外が外に出ないこと
3. `sourceReportsVersionHintOn404` — 404 を表すエラーを投げるスタブで、`sourceError` に版を示す文言が入ること
4. `sourceReportsSourceErrorOnBadPayload` — JSON でない Data を返すスタブで、`accounts` が空になり `sourceError` が非 nil になること
5. `sourceReportsPartialReadAsSourceError` — 1 件だけ壊れたフィクスチャを返すスタブで、`accounts` が 1 件でありながら `sourceError` が非 nil になること

### 8.5 既存ファイル BarTitleFormatterTests.swift への追加

1. `sourceErrorWithoutAccountsIsError` — `sourceError` 非 nil かつアカウント 0 件のスナップショットで、`make` の severity が `.error`、`icon` の severity も `.error` で fraction が nil になること
2. `sourceErrorWithAccountsKeepsDataSeverity` — `sourceError` 非 nil でアカウントがあるとき、severity がデータ本来の値になること。`.stale` に落ちないこと
3. `retainingWindowsCarriesWholeSnapshotOnSourceError` — 前回データありで今回 `sourceError` かつ 0 件のとき、前回のアカウントが丸ごと残り、`generatedAt` が前回の値のままで、`sourceError` が保たれること
4. `retainingWindowsIgnoresSourceErrorWhenAccountsPresent` — `sourceError` があってもアカウントが読めているときは、丸ごと引き継ぎの枝に入らず既存のアカウント単位の挙動になること

### 8.6 既存テストへの影響

**壊れるテストは無い。** 根拠は次のとおり。

- `UsageSnapshot.sourceError` は `init` の末尾に既定値付きで足す。既存テストはすべてラベル付きの呼び出しなので、そのままコンパイルされる。位置引数で `init` を呼んでいる箇所は 1 つも無い
- `emptySnapshotIsStaleWithEmptyText` は `UsageSnapshot.empty` を使う。`sourceError` は nil なので `.stale` のまま変わらない
- `iconIsErrorOrStaleWithoutData` も同じ理由で変わらない
- `BarTitleFormatter.windowSeverity` を 1 行も変えないので、閾値まわりのテストはすべて無傷である
- `AccountUsage`、`RateWindow`、`RateWindowKind`、`AccountBarMode` に変更が無いので、それらを組み立てるヘルパー `win` と `account` も無傷である
- `UsageParsingTests` は `UsageAPIClient.mapLimits` と `ConfigDiscovery.discover` を直接呼ぶ。どちらも今回変更しない。`ConfigDiscovery` と `KeychainReader` は `LocalConfigUsageSource` へ呼び出し元が移るだけで、型そのものは触らない
- `KeychainServiceTests` は無関係である

**コンパイルが壊れる箇所は無い。** `AccountBarMode` に case を足さないので `BarTitleFormatter.selectedAccount` の網羅的 `switch` も無傷である。`retainingWindows` は `Models.swift:123-125` で `AccountUsage` を組み直しているが、`AccountUsage` にフィールドを足さないのでそのままでよい。

### 8.7 テストしない範囲

`TeamclaudeQuotaClient` の実 URLSession 呼び出しと `KeychainReader` の外部プロセス実行はユニットテストしない。既存の `UsageAPIClient.fetchWindows` も同じ理由でテストされていない。ここは 9.4 と 9.5 の実機検証で担保する。

## 9. 実装ステップ

### 9.1 Core

1. **`Sources/ClaudeUsageBarCore/Models.swift`** — `UsageSnapshot.sourceError` を `init` 末尾に既定値 nil で追加。`retainingWindows(from:)` の先頭に丸ごと引き継ぎの分岐を足す。依存なし
2. **`Sources/ClaudeUsageBarCore/BarTitleFormatter.swift`** — `make` の `:26-28` と `icon(from:settings:)` の `:74` で、アカウント 0 件のときの severity を `sourceError` の有無で `.error` と `.stale` に分ける。他は触らない。依存: 1
3. **`Sources/ClaudeUsageBarCore/UsageSource.swift`** 新規 — `protocol UsageSource: Sendable` と `enum UsageSourceKind`。依存: 1
4. **`Sources/ClaudeUsageBarCore/LocalConfigUsageSource.swift`** 新規 — 現在の `UsageService.snapshot()` の本体を `UsageService.swift:18-70` からそのまま移す。ロジックは 1 行も変えない。`sourceError` は常に nil。依存: 3
5. **`Sources/ClaudeUsageBarCore/UsageService.swift`** — 中身を 3.2 の合成ルートに置き換える。依存: 3, 4
6. **`Sources/ClaudeUsageBarCore/TeamclaudeConfig.swift`** 新規 — `defaultPort` と `resolvePort(environment:homeDirectory:)`。4.3 のポート解決と秘匿の規則に従う。依存なし
7. **`Sources/ClaudeUsageBarCore/TeamclaudeQuotaClient.swift`** 新規 — `Failable<T>`、Decodable 群、`mapQuota(_:now:) throws -> QuotaResult`、実 URLSession を使う `fetch(port:)`。4 節と 6 節の全規則がここに集約される。依存: 1
8. **`Sources/ClaudeUsageBarCore/TeamclaudeUsageSource.swift`** 新規 — `transport` クロージャを持ち、`snapshot(now:)` で失敗を `sourceError` に落とす。4.7 の表の文言をここで作る。依存: 3, 6, 7

### 9.2 App

9. **`Sources/ClaudeUsageBar/SettingsStore.swift`** — `Key.usageSource` と `@Published var usageSource` を追加。`init` で読み出す。`effectiveAccountMode` を追加し、`displaySettings` の `accountMode` をそれに差し替える。依存: 3
10. **`Sources/ClaudeUsageBar/SettingsView.swift`** — `Usage Source` セクションを `General` の直後に追加。`Account` ピッカーで teamclaude 選択時に `.active` の行を出さず、理由のキャプションを添える。依存: 9
11. **`Sources/ClaudeUsageBar/StatusItemController.swift`** — `currentSource` を保持。sink で情報源の変化を検知してスナップショットをクリアし再取得。`refresh()` で情報源を捕まえて完了時に照合。`UsageService(source)` に差し替え。依存: 5, 9
12. **`Sources/ClaudeUsageBar/PopoverView.swift`** — `sourceError` バナー、空状態の文言変更、`No usage data yet` の 3 点。依存: 1

### 9.3 テスト

13. **`Tests/ClaudeUsageBarCoreTests/`** — 8 節の 3 つの新規ファイルと `BarTitleFormatterTests.swift` への追加。`./Scripts/test.sh` が全緑になること。依存: 1 から 8

`Package.swift` は変更しない。ターゲット構成もフィクスチャの resources 宣言も増えない。

### 9.4 loopback 疎通の実機確認

これはステップ 11 の直後に行う。情報源の切り替え UI が揃ってはじめて実施できる。結果によってはパッケージング側の変更が要るためである。

macOS の App Transport Security が `http://127.0.0.1:<port>` への平文リクエストを拒否するかどうかを実測していない。IP リテラル宛の平文が許されるという理解はあるが、確認していない。

手順

1. `./Scripts/run_local.sh debug` でメニューバーに起動する
2. 情報源を `teamclaude pool` に切り替える
3. ポップオーバーにアカウントが出れば ATS は問題ない
4. `sourceError` に接続エラーが出る場合、`Console.app` で `NSURLErrorAppTransportSecurityRequiresSecureConnection`、つまりエラーコード `-1022` が出ていないか確認する

`-1022` が出た場合は `Scripts/package_app.sh:48` から始まる Info.plist の生成部に次を足す。

```
<key>NSAppTransportSecurity</key>
<dict><key>NSAllowsLocalNetworking</key><true/></dict>
```

`swift run ClaudeUsageBar` で起動したバイナリは Info.plist を持たないので ATS の設定ができない。確認は必ず `run_local.sh` を経由した .app バンドルで行う。

macOS 15 以降のローカルネットワークアクセスの許可ダイアログは loopback 宛には出ないと理解しているが、これも手順 3 で同時に確認できる。ダイアログが出たら許可すればよく、設計変更は要らない。

### 9.5 実機での目視確認

CLAUDE.md の方針どおり、App ターゲットにはユニットテストが無いので実起動で確認する。メニューバーのライト状態とダーク状態の両方で見る。

1. 情報源 `.local` のまま、既存の表示が変わっていないこと
2. 情報源 `.teamclaude` に切り替えた瞬間にバーが更新されること。次のタイマー発火を待たないこと
3. プールのアカウントが全件並び、5h / Week(all) / Week(Fable) の 3 行が出ること。Week(Sonnet) の行が出ないこと
4. `Account` ピッカーから `Active (most constrained)` が消え、キャプションが出ていること。ポップオーバーにプール全アカウントが並ぶこと。バーは既存仕様どおり 2 行まで
5. teamclaude を止めた状態でリフレッシュしたとき、数値が残ったままバナーが出ること。フッターの `Updated` が前回の時刻のままであること
6. teamclaude を止めたままアプリを再起動したとき、赤い Clawd とバナーだけになること
7. 情報源を `.local` に戻したとき、プールのアカウントが残らないこと。`Account` ピッカーの選択が `.active` に戻っていること

## 10. 判断の記録

### 10.1 採用した案とその理由

| 論点 | 採用 | 理由の要点 |
| --- | --- | --- |
| 情報源の境界 | Core に `UsageSource` protocol を 1 つ | 2 経路は依存の集合が別物。テストの継ぎ目が要る |
| teamclaude の読み口 | `/teamclaude/quota` 1 本 | バケット整形済み。マッパーが 1 つで済む。status にしか無い情報は全部非ゴール |
| ポート解決 | `proxy.port` だけ読み、失敗は黙って 3456 | 同一ファイルにトークンがある。エラー文言も出力しない |
| 0〜1 の変換 | `mapQuota` の 1 か所でクランプ付き | `usedPercent` 0...100 の契約を境界の外に漏らさない |
| Fable の overage | 100 にクランプ | 契約維持の価値が、超過量を見せる価値を上回る |
| `remaining` | 読まない | `remainingPercent` を唯一の真実にする。丸め差の食い違いを作らない |
| `weeklySonnet` | 出さない | `source` が `unified7d` で Sonnet 固有の値ではない。画面に出ないまま色を動かす |
| 未観測のバケット | ウィンドウを作らない | 0% は嘘になる |
| `severity` / `isActive` | 常に nil と false | quota エンドポイントに対応する情報が無い。`windowSeverity` を 1 行も変えずに済む |
| `folders` | 常に `[]` | config dir が対応しないアカウントがある |
| アカウント識別子 | `name` をそのまま `email` に | `(Org)` 付きの形が Identifiable の一意性を担っている |
| 404 の扱い | 版を示す専用メッセージ、フォールバックなし | 原因がほぼ確実に版の古さ。2 本目のマッパーを作らない |
| 情報源の設定の置き場 | `DisplaySettings` の外 | 整形の契約に取得の関心を混ぜない |
| accountMode の `.active` | 永続値を書き換えず読み出し時に `.all` へ読み替え | 情報源を戻すと元に戻る |
| `.active` の UI | 行を消してキャプションで理由を書く | `Picker` 内の `.disabled` は効かないことがある |
| 版差への耐性 | 読まないキーは型に書かない。全 optional。要素単位 failable | 版番号での分岐は未検証パスを増やす |

### 10.2 却下した案とその理由

1. **`/teamclaude/status` を併用して `currentAccount` を出す。** アクティブ表示が非ゴールになった時点で、status にしか無い情報のうち表示に使うものがゼロになった。2 本目のリクエストとマッパーは、安定性の約束が無い API に対する腐りうる面を 2 倍にするだけである
2. **`state.json` を HTTP のフォールバックにする。** v1.1.17 で atomic write になり破損レースは消えたが、生の `unified*` から自前で仕分ける第 2 のマッパーが要る。1 と同じ理由で却下した
3. **404 のときに `/teamclaude/status` へフォールバックする。** v1.1.16 以前を延命するためだけに 2 つ目のマッパーを維持することになる。ユーザーが動かしているのは v1.1.17 である。版を上げてもらうほうが正しい
4. **`UsageService` の中で enum switch する。** protocol を増やさない点は既存方針に沿うが、片方の経路だけをスタブに差し替えられずテストできない
5. **`UsageAPIClient` に teamclaude 用メソッドを足す。** Anthropic API のクライアントに別サービスが混ざり、`UsageAPIError` の意味も濁る
6. **`aggregate` を表示する。** プール全体の重み付き残量は魅力的だが、要件に含まれていない。表示するには `accountMode` に「プール合計」という新しい選択肢が要り、`AccountUsage` に相当しない行をポップオーバーに置くことになる。`capacityWeight` と `weight` の意味を UI で説明する必要も生じる。迷ったら使わない側に倒すという方針に従って却下した
7. **`RateWindow.usedPercent` の上限を緩めて overage を表示する。** ゲージ描画、アイコンの fraction、既存テストのすべてに波及して、得られるのは超過量だけ
8. **`status` と `tier` を読む。** `status` は実測値が `"active"` の 1 つだけで語彙が不明。値が入ったときの型を確認できていないフィールドを結線すると、検証できない分岐が残る。`tier` は集計を表示しない以上使い道が無い
9. **`weeklySonnet` をウィンドウ化する。** ポップオーバーに出ないまま `mostConstrainedWindow` と `iconWindow` の候補に入り、画面に理由の出ない色変化を生む。しかも値は `weeklyShared` と同じである
10. **`AccountUsage.orgName` を足してポップオーバーに出す。** `email` に `(Org)` が含まれるので既に読める。フィールドを増やす価値が無い
11. **`utilization + remaining == 1` を検証して単位変更を検出する。** 検出のためだけに 2 つ目の真実を持ち込むと、丸め差で偽陽性を出す新しい失敗モードが増える
12. **teamclaude の版番号で読み方を分岐する。** CHANGELOG も API リファレンスも無く、版番号は形の保証にならない。未検証のコードパスが増えるだけ
13. **設定画面で teamclaude を自動検出して選択肢を出し分ける。** ユーザーが明示的な選択を要件にしている。設定画面に非同期処理を持ち込む必要も生じる
14. **`.active` の行を残して `.disabled(true)` を付ける。** SwiftUI の `Picker` の `.menu` スタイルで効かないことがある。選べてしまう無効行より、消えた理由が書いてあるほうが確実
15. **`accountMode` の永続値を teamclaude 切り替え時に `.all` へ書き換える。** 情報源を戻したときに元の選択が失われる
16. **非既定ポート向けの隠し UserDefaults キー。** 発見不能な設定は負債になる
17. **フィクスチャを resources ファイルとして置く。** `Package.swift` の変更が要る。既存テストは文字列リテラルで足りている

### 10.3 受け入れたリスク

1. **`utilization` の単位が 0〜1 から 0〜100 に変わったら検出できない。** 全アカウントが常に 100% critical という、誰が見ても異常と分かる表示になる。中途半端に正しく見えるより発見が早い
2. **teamclaude の一時的な不応答で数値が消える。** 丸ごと引き継ぎで直前の値を保持し、ポップオーバーのバナーで事情を出す。初回起動直後だけは引き継ぐ値が無く `.error` になる
3. **v1.1.16 以前では動かない。** 404 で版を示すメッセージが出る。フォールバック経路は持たない
4. **overage の量が失われる。** 100% 表示で critical という結論は変わらない
5. **非既定ポート かつ 非既定の設定ファイルパス かつ Finder 起動で teamclaude を見つけられない。** 3 条件が揃う確率が極めて低い。実際に起きたら設定 UI にポート欄を足す
6. **`.all` モードで同一メール複数組織のラベルが衝突する。** `accountLabel` が email のローカル部にフォールバックするため、`a@example.com (X)` と `a@example.com (Y)` がどちらも `a` になる。`.all` は 2 行までの表示であり、ポップオーバーでは組織名込みで区別できる
7. **情報源をまたいだ pin が外れる。** most constrained にフォールバックしてバーは動き続ける
8. **`disabled` の型が将来変わると decode に影響する。** 実測で Bool の `false` を確認しているキーなので仮定の強度が高い。要素単位の failable decode があるので、影響は該当アカウント 1 件に留まる
9. **ATS が loopback の平文を拒否する可能性が未検証。** 9.4 で確認し、拒否されたら Info.plist に `NSAllowsLocalNetworking` を足す
