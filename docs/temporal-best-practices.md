# Temporal 運用ナレッジ・ベストプラクティスレポート

> 調査日: 2026-02-24
> 調査対象: coinbase/temporal-ruby, temporalio/sdk-ruby, Temporal 公式ドキュメント, コミュニティ知見

---

## 目次

1. [Continue-as-New の適切な使い方](#1-continue-as-new-の適切な使い方)
2. [Activity のタイムアウト設計](#2-activity-のタイムアウト設計)
3. [リトライポリシーのベストプラクティス](#3-リトライポリシーのベストプラクティス)
4. [Workflow の決定論性（Determinism）の制約](#4-workflow-の決定論性determinismの制約)
5. [シグナル・クエリの使い方](#5-シグナルクエリの使い方)
6. [ワーカーのスケーリングと並行性](#6-ワーカーのスケーリングと並行性)
7. [エラーハンドリングのパターン](#7-エラーハンドリングのパターン)
8. [大きなペイロードの扱い](#8-大きなペイロードの扱い)
9. [バージョニングとデプロイ戦略](#9-バージョニングとデプロイ戦略)
10. [監視・オブザーバビリティ](#10-監視オブザーバビリティ)
11. [multichain-indexer への改善提案](#11-multichain-indexer-への改善提案)

---

## 1. Continue-as-New の適切な使い方

### なぜ必要か

- Event History は **51,200 イベント** または **50 MB** が上限（10,240 イベント / 10 MB で警告）
- 巨大な History は Worker 障害時のリプレイに時間がかかり、パフォーマンスが劣化する

### いつ使うか

- **長期実行ワークフロー**: ポーリング、定期処理、無限ループ系のワークフロー
- **イベント数が増え続ける場合**: ループ内で Activity を繰り返し呼ぶパターン
- 目安: **数千イベントを超える前** に Continue-as-New を発行する

### Ruby SDK での使い方

```ruby
# Workflow 内から ContinueAsNewError を raise する
raise Temporalio::Workflow::ContinueAsNewError.new(next_arg1, next_arg2)
```

### 注意点

- **Update ハンドラ内では使えない** — メインの Workflow メソッドから呼ぶこと
- Continue-as-New 前に **すべてのハンドラを完了** させること
- 状態を引き継ぐ場合は引数として渡す（History はリセットされる）
- 子ワークフローやタイマーが残っている状態で呼ぶと予期しない動作になりうる

### パターン例: ブロックチェーンインデクサ

```ruby
class IndexerWorkflow < Temporalio::Workflow::Definition
  def execute(last_block:, iteration: 0)
    loop do
      last_block = Temporalio::Workflow.execute_activity(
        IndexBlocksActivity, last_block,
        start_to_close_timeout: 60
      )
      
      # 1000イテレーションごとに Continue-as-New
      if iteration >= 1000
        raise Temporalio::Workflow::ContinueAsNewError.new(
          last_block: last_block, iteration: 0
        )
      end
      iteration += 1
      
      Temporalio::Workflow.sleep(1) # 次のポーリングまで待機
    end
  end
end
```

---

## 2. Activity のタイムアウト設計

Temporal には 4 種類の Activity タイムアウトがある：

| タイムアウト | 用途 | 推奨 |
|---|---|---|
| **Start-to-Close** | 1回の Activity 実行の最大時間 | **常に設定すべき** |
| **Schedule-to-Close** | リトライ含む全体の最大時間 | リトライ制御に最適 |
| **Heartbeat** | ハートビート間の最大間隔 | 長時間 Activity に必須 |
| **Schedule-to-Start** | Task Queue での待ち時間の上限 | ほぼ不要（監視で代替） |

### 設計指針

1. **Start-to-Close は必ず設定する**
   - Worker がクラッシュした場合の検出に必要
   - Activity の最大実行時間より少し長めに設定
   - 例: 通常 5 秒で終わる → `start_to_close_timeout: 30`

2. **Schedule-to-Close でリトライ全体を制限する**
   - `maximum_attempts` よりも **Schedule-to-Close で時間ベースの制限** を推奨
   - ユーザー体験に直結する（「最大 N 分待てる」の方が直感的）

3. **長時間 Activity には Heartbeat を使う**
   - 5分以上かかりうる Activity には Heartbeat + Heartbeat Timeout を設定
   - Start-to-Close を 5 時間に設定するより、Heartbeat Timeout 30 秒の方が障害検出が速い
   - 進捗情報を Heartbeat に含めてリトライ時の再開に活用

```ruby
# 短い Activity
Temporalio::Workflow.execute_activity(
  FetchPriceActivity, token_id,
  start_to_close_timeout: 10,
  schedule_to_close_timeout: 120
)

# 長時間 Activity
Temporalio::Workflow.execute_activity(
  ProcessLargeDataActivity, batch_id,
  start_to_close_timeout: 3600,
  heartbeat_timeout: 30,
  retry_policy: Temporalio::RetryPolicy.new(max_interval: 60)
)
```

4. **Schedule-to-Start は基本的に設定しない**
   - Worker のスケーリングで対処する
   - 代わりに `temporal_activity_schedule_to_start_latency` メトリクスを監視

---

## 3. リトライポリシーのベストプラクティス

### デフォルト値（Activity）

| 属性 | デフォルト |
|---|---|
| Initial Interval | 1 秒 |
| Backoff Coefficient | 2.0 |
| Maximum Interval | 100 × Initial Interval (100秒) |
| Maximum Attempts | 無制限 |
| Non-Retryable Errors | なし |

### ベストプラクティス

1. **Activity はデフォルトでリトライされる** — 明示的に設定しなくてもOK
2. **Workflow にはリトライポリシーを設定しない**（通常不要）
3. **リトライ回数より時間で制限する** — `schedule_to_close_timeout` を使う
4. **永続的エラーは Non-Retryable にする** — リトライしても無駄なものを即座に失敗させる

```ruby
# Non-retryable エラーの発生
raise Temporalio::Error::ApplicationError.new(
  "Invalid credit card: #{card_number}",
  type: 'InvalidInput',
  non_retryable: true
)

# リトライポリシーで特定エラーを除外
Temporalio::Workflow.execute_activity(
  ChargeCardActivity, amount,
  start_to_close_timeout: 30,
  retry_policy: Temporalio::RetryPolicy.new(
    initial_interval: 1,
    backoff_coefficient: 2.0,
    maximum_interval: 60,
    non_retryable_error_types: ['InvalidInput', 'InsufficientFunds']
  )
)
```

5. **next_retry_delay でリトライ間隔を動的に制御できる**

```ruby
raise Temporalio::Error::ApplicationError.new(
  'Rate limited',
  type: 'RateLimited',
  next_retry_delay: 3 * Temporalio::Activity::Context.current.info.attempt
)
```

---

## 4. Workflow の決定論性（Determinism）の制約

### 絶対にやってはいけないこと

Workflow コード内で以下を行うと **非決定論的エラー** が発生する：

| ❌ 禁止 | ✅ 代替手段 |
|---|---|
| ネットワークリクエスト | Activity として実行 |
| DB クエリ | Activity として実行 |
| `Time.now` / `rand` | `Temporalio::Workflow.now` / Workflow 内のシード付き乱数 |
| スレッド生成 | Fiber（公式 SDK の Durable Fiber） |
| グローバル変数の変更 | Workflow のインスタンス変数を使用 |
| 非決定論的なライブラリ呼び出し | Activity に委譲 |
| `sleep` / `IO.select` | `Temporalio::Workflow.sleep` |

### なぜ決定論が必要か

- Workflow はリプレイ時に **同じコードを再実行** して状態を復元する
- 非決定論的なコードがあると、リプレイ時に異なるパスを通り **NonDeterminismError** が発生
- Activity の結果はリプレイ時に History から取得される（再実行されない）

### 公式 Ruby SDK の安全機構

- **Durable Fiber Scheduler**: Workflow 内の Fiber を安全に管理
- **Illegal Call Tracing**: 不正な呼び出し（IO など）を検出してエラーにする
- Workflow 内のコードは自動的にサンドボックス化される

### よくある落とし穴

1. **ログ出力に Time.now を使う** → `Temporalio::Workflow.now` を使う
2. **Hash の順序に依存する** → Ruby の Hash は挿入順だが、リプレイで変わりうるケースに注意
3. **条件分岐で外部状態を参照する** → Signal/Query で状態を受け取る
4. **gem のバージョンアップで内部動作が変わる** → Replay テストで検証

---

## 5. シグナル・クエリの使い方

### シグナル（Signal）

外部から Workflow に **非同期メッセージ** を送る手段。Workflow の状態を変更できる。

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  workflow_signal
  def cancel_order(reason)
    @cancelled = true
    @cancel_reason = reason
  end

  def execute(order_id)
    @cancelled = false
    # ... 処理中にシグナルを受け取れる
    Temporalio::Workflow.wait_condition { @cancelled || @completed }
  end
end

# クライアントからシグナル送信
handle = client.workflow_handle('order-123')
handle.signal('cancel_order', 'Customer requested')
```

**ユースケース**: キャンセル、承認、外部イベント通知

### クエリ（Query）

Workflow の **現在の状態を同期的に読み取る** 手段。状態を変更してはいけない。

```ruby
class OrderWorkflow < Temporalio::Workflow::Definition
  workflow_query
  def status
    @current_status
  end
end

# クライアントからクエリ
result = handle.query('status')
```

**ユースケース**: 進捗確認、ステータス表示、デバッグ

### Update（新機能）

Signal + Query を組み合わせた概念。状態変更 + 結果の返却が可能。

### 注意点

- Signal ハンドラ内で長時間ブロックしない
- Query ハンドラ内で **状態を変更しない**（副作用禁止）
- Signal-with-Start で Workflow の開始とシグナル送信を原子的に実行可能

---

## 6. ワーカーのスケーリングと並行性

### Coinbase temporal-ruby のワーカー設定

```ruby
Temporal::Worker.new(
  activity_thread_pool_size: 20,    # Activity ポーリングスレッド数
  workflow_thread_pool_size: 10,    # Workflow ポーリングスレッド数
  activity_max_tasks_per_second: 0  # レート制限（0=無制限）
)
```

### スケーリング戦略

1. **水平スケーリング**: 同じ Task Queue に対して複数の Worker プロセスを起動
   - Temporal が自動的にタスクを分散
   - Worker の追加/削除が容易

2. **Task Queue の分離**:
   - CPU 集約型と IO 集約型の Activity を別の Task Queue に分ける
   - 優先度の異なるワークフローを別の Task Queue にルーティング

3. **並行性の制御**:
   - `activity_thread_pool_size` で同時実行 Activity 数を制限
   - `workflow_thread_pool_size` で同時実行 Workflow タスク数を制限
   - `activity_max_tasks_per_second` で外部 API のレート制限に対応

4. **スケーリング指標**:
   - `temporal_activity_schedule_to_start_latency` が増加 → Worker が足りない
   - Task Queue のバックログを監視

### 注意点

- Workflow Worker は CPU バウンド（リプレイ処理）— メモリと CPU に注意
- Activity Worker は IO バウンドが多い — スレッド数を多めに設定可能
- Worker プロセスは SIGTERM/SIGINT でグレースフルシャットダウンされる

---

## 7. エラーハンドリングのパターン

### 基本原則

- **Activity の失敗は Workflow の失敗に直結しない** — これが Temporal の設計思想
- Activity はリトライポリシーに基づいてリトライされ、すべて失敗した後にのみ Workflow にエラーが返る
- Workflow は **明示的に ApplicationError を raise した場合のみ** Failed になる

### パターン 1: Saga パターン（補償トランザクション）

```ruby
class TransferWorkflow < Temporalio::Workflow::Definition
  def execute(from, to, amount)
    Temporalio::Workflow.execute_activity(DebitActivity, from, amount, start_to_close_timeout: 30)
    Temporalio::Workflow.execute_activity(CreditActivity, to, amount, start_to_close_timeout: 30)
  rescue StandardError => e
    # 補償: デビットを取り消し
    Temporalio::Workflow.execute_activity(RefundActivity, from, amount, start_to_close_timeout: 30)
    raise Temporalio::Error::ApplicationError.new("Transfer failed: #{e.message}")
  end
end
```

### パターン 2: Non-Retryable エラーで即座に失敗

```ruby
# Activity 内
raise Temporalio::Error::ApplicationError.new(
  'Bad input data',
  non_retryable: true
)
```

### パターン 3: Workflow Task の失敗 vs Workflow の失敗

- Workflow 内で `RuntimeError` 等が raise されると **Workflow Task が失敗**（Workflow 自体は継続）
- Temporal はバグ修正のデプロイを待ってリトライしてくれる
- `ApplicationError` を raise すると **Workflow 自体が失敗**

### パターン 4: Activity のべき等性

```ruby
class ProcessPaymentActivity < Temporalio::Activity::Definition
  def execute(payment_id)
    # べき等キーを使って重複実行を防ぐ
    idempotency_key = Temporalio::Activity::Context.current.info.activity_id
    PaymentService.charge(payment_id, idempotency_key: idempotency_key)
  end
end
```

Coinbase SDK では `activity.run_idem` / `activity.workflow_idem` でべき等トークンを取得可能。

---

## 8. 大きなペイロードの扱い

### 制限値

| 項目 | 上限 |
|---|---|
| 単一ペイロード（引数/戻り値） | **2 MB** |
| Event History トランザクション | **4 MB** |
| gRPC メッセージ | **4 MB** |
| Event History 全体 | **50 MB / 51,200 イベント** |

### 4MB 超過時の動作

- Workflow Task のレスポンスが 4 MB を超えると **Workflow が自動的に Terminate** される
- **回復不能** — リトライしても解決しない

### 対処法

1. **大きなデータは外部ストレージに退避**
   - Activity の引数/戻り値にデータ本体を渡さない
   - S3/GCS/Redis 等に保存し、参照（URL/キー）だけを渡す

```ruby
# ❌ 悪い例
result = Temporalio::Workflow.execute_activity(
  FetchAllTransactionsActivity, block_number,  # 巨大なデータが返る
  start_to_close_timeout: 60
)

# ✅ 良い例
s3_key = Temporalio::Workflow.execute_activity(
  FetchAndStoreTransactionsActivity, block_number,  # S3 キーだけ返す
  start_to_close_timeout: 60
)
```

2. **Payload Codec で圧縮する**
   - カスタム PayloadCodec で gzip 圧縮を適用
   - 一時的な対処であり、根本解決にはならない

3. **バッチ分割**
   - 大量の Activity を一度にスケジュールしない
   - 小さなバッチに分けて `Temporalio::Workflow.sleep(0.001)` で Workflow Task を分割

4. **Child Workflow で分割**
   - 大規模処理を Child Workflow に分散
   - 各 Child Workflow が独自の Event History を持つ

---

## 9. バージョニングとデプロイ戦略

### 3 つの戦略

#### 1. Patching API（推奨）

既存の Workflow を安全に更新する標準的な方法。

```ruby
class MyWorkflow < Temporalio::Workflow::Definition
  def execute
    if Temporalio::Workflow.patched('v2-new-activity')
      # 新しいコードパス
      Temporalio::Workflow.execute_activity(NewActivity, start_to_close_timeout: 100)
    else
      # 古いコードパス（既存の実行用）
      Temporalio::Workflow.execute_activity(OldActivity, start_to_close_timeout: 100)
    end
  end
end
```

**3 ステップのライフサイクル:**
1. `patched()` で新旧コードを共存 → デプロイ
2. 旧 Workflow が全て完了したら `deprecate_patch()` に変更
3. リテンション期間後にパッチコードを完全削除

#### 2. Worker Versioning

Worker をバージョンタグで管理し、古い Worker と新しい Worker を並行稼働させる。

- Temporal がバージョンに基づいてルーティング
- コードにパッチ分岐が不要

#### 3. Workflow 名ベースのバージョニング

```ruby
# 完全に新しい Workflow として登録
class IndexerWorkflowV2 < Temporalio::Workflow::Definition
  # ...
end
```

- シンプルだがコード重複が発生
- 既存の実行中 Workflow には影響しない

### Replay テスト

デプロイ前に必ず **Replay テスト** を実行して非決定論エラーを検出する。

---

## 10. 監視・オブザーバビリティ

### メトリクス

公式 Ruby SDK は OpenTelemetry をサポート：

- **`temporal_activity_schedule_to_start_latency`**: Worker の不足を検出
- **`temporal_workflow_task_schedule_to_start_latency`**: Workflow Worker の不足を検出
- **`temporal_activity_execution_failed`**: Activity 失敗率
- **`temporal_workflow_completed`** / **`temporal_workflow_failed`**: Workflow 成功/失敗率

### トレーシング

```ruby
# OpenTelemetry 統合
require 'temporalio'

# クライアント作成時に telemetry を設定
runtime = Temporalio::Runtime.new(
  telemetry: Temporalio::Runtime::TelemetryOptions.new(
    metrics: Temporalio::Runtime::MetricsOptions.new(
      opentelemetry: Temporalio::Runtime::OpenTelemetryMetricsOptions.new(
        # OpenTelemetry meter provider を渡す
      )
    )
  )
)
```

### ログ

- Workflow 内では `Temporalio::Workflow.logger` を使用
- リプレイ時にログが重複しないよう SDK が制御

### Web UI

- Temporal Web UI でワークフローの状態、Event History、保留中の Activity を確認
- Search Attributes でカスタムフィルタリング

### 推奨アラート

| アラート条件 | 意味 |
|---|---|
| schedule_to_start_latency > 閾値 | Worker 不足 |
| Activity 失敗率の急上昇 | 外部依存の障害 |
| Workflow の長期停滞 | バグまたはリソース不足 |
| Event History サイズ警告 | Continue-as-New が必要 |

---

## 11. multichain-indexer への改善提案

multichain-indexer はブロックチェーンのインデクシング処理を Temporal で管理するプロジェクトと想定。以下の具体的な改善を提案する。

### 11.1 Continue-as-New の導入

**課題**: チェーンの継続的なインデクシングは無限ループになるため、Event History が肥大化する

**対策**:
- N ブロック処理ごと（例: 1,000 ブロック）に Continue-as-New を実行
- 最後に処理したブロック番号を引数として引き継ぐ
- Event History サイズの監視アラートを設定

### 11.2 Activity タイムアウトの最適化

| Activity | 推奨設定 |
|---|---|
| RPC ノードへのブロック取得 | `start_to_close: 30s`, `schedule_to_close: 300s` |
| トランザクション解析 | `start_to_close: 60s` |
| DB 書き込み | `start_to_close: 30s`, `heartbeat: 10s`（バッチの場合） |
| 外部 API 呼び出し | `start_to_close: 15s`, `schedule_to_close: 120s` |

### 11.3 ペイロードサイズの管理

**課題**: ブロックデータ（特にトランザクション数が多いブロック）は簡単に 2MB を超える

**対策**:
- ブロックデータを直接 Activity の戻り値にしない
- RPC から取得 → DB/S3 に保存 → 参照キーのみ返す
- チェーンごとの最大ブロックサイズを考慮した設計

### 11.4 チェーンごとの Task Queue 分離

```ruby
# チェーンごとに Task Queue を分ける
worker_eth = Temporalio::Worker.new(
  client:, task_queue: 'indexer-ethereum',
  workflows: [IndexerWorkflow], activities: [IndexBlockActivity]
)

worker_polygon = Temporalio::Worker.new(
  client:, task_queue: 'indexer-polygon',
  workflows: [IndexerWorkflow], activities: [IndexBlockActivity]
)
```

**メリット**:
- チェーンごとに独立してスケール可能
- 1 チェーンの障害が他に波及しない
- チェーン特有のレート制限に対応可能

### 11.5 リトライとレート制限

```ruby
# RPC ノードのレート制限対応
raise Temporalio::Error::ApplicationError.new(
  'RPC rate limited',
  type: 'RateLimited',
  next_retry_delay: retry_after_seconds  # RPC のレスポンスヘッダから取得
)
```

- RPC ノードの 429 レスポンスに `next_retry_delay` で対応
- 恒久的なエラー（不正なブロック番号等）は `non_retryable: true`

### 11.6 Signal を使ったリアルタイム制御

```ruby
class IndexerWorkflow < Temporalio::Workflow::Definition
  workflow_signal
  def pause;  @paused = true;  end
  
  workflow_signal
  def resume; @paused = false; end
  
  workflow_signal  
  def reindex(from_block)
    @reindex_from = from_block
  end
  
  workflow_query
  def status
    { last_block: @last_block, paused: @paused, lag: @chain_head - @last_block }
  end
end
```

**ユースケース**:
- 障害時の一時停止/再開
- 特定ブロックからの再インデクシング指示
- 現在の同期状態のクエリ

### 11.7 バージョニング戦略

- インデクサのロジック変更時は **Patching API** を使用
- 大幅なスキーマ変更時は **新しい Workflow 名** (`IndexerWorkflowV2`) で切り替え
- **Replay テスト** を CI に組み込み、デプロイ前に非決定論を検出

### 11.8 監視ダッシュボード

以下のメトリクスを Grafana/Datadog 等で可視化：

- **インデクシング遅延**: `chain_head_block - last_indexed_block`（Search Attribute + Query）
- **Activity 失敗率**: チェーンごと・Activity タイプごと
- **Worker のスケジュールレイテンシ**: Task Queue ごと
- **Event History サイズ**: Continue-as-New の必要性判断

---

## まとめ: 重要度順チェックリスト

| 優先度 | 項目 | 対応 |
|---|---|---|
| 🔴 高 | Start-to-Close タイムアウトを全 Activity に設定 | 未設定は Worker 障害時にスタックする |
| 🔴 高 | Continue-as-New をループ系 Workflow に導入 | History 上限超過で Workflow が死ぬ |
| 🔴 高 | 大きなペイロードを外部ストレージに退避 | 4MB 超過で回復不能な Terminate |
| 🟡 中 | Non-Retryable エラーの定義 | 無駄なリトライの削減 |
| 🟡 中 | Heartbeat を長時間 Activity に追加 | 障害検出の高速化 |
| 🟡 中 | Patching API + Replay テストの導入 | 安全なデプロイのため |
| 🟡 中 | チェーンごとの Task Queue 分離 | 障害の分離とスケーリング |
| 🟢 低 | Signal/Query の活用 | 運用の利便性向上 |
| 🟢 低 | OpenTelemetry 統合 | オブザーバビリティ向上 |
| 🟢 低 | Activity のべき等性の確保 | データ整合性の向上 |
