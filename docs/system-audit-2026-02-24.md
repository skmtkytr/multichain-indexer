# Multichain Indexer — システム監査レポート

**日付**: 2026-02-24  
**対象**: `skmtkytr/multichain-indexer` (commit c6ec4f7)  
**コード規模**: ~4,750行 Ruby / 24 migrations / 1,389行 Dashboard HTML

---

## 1. アーキテクチャ概要

```
┌──────────────┐     ┌──────────┐     ┌──────────────┐
│  Dashboard   │────▶│ Rails API│────▶│  PostgreSQL   │
│  (port 3000) │     │  (Puma)  │     │  (port 5432)  │
└──────────────┘     └──────────┘     └───────┬───────┘
                                              │
┌──────────────┐     ┌──────────┐             │
│ Temporal UI  │────▶│ Temporal │             │
│  (port 8080) │     │ (7233)   │◀────────────┤
└──────────────┘     └──────────┘             │
                          ▲                   │
                          │                   │
                     ┌────┴────┐              │
                     │ Worker  │──────────────┘
                     │(7 queues)│
                     └─────────┘
                          │
              ┌───────────┼───────────┐
              ▼           ▼           ▼
         EVM RPCs    Bitcoin RPCs  Substrate
                                   Sidecar
```

**サポートチェーン**: EVM (6) / UTXO (4) / Substrate (1) = 11チェーン定義  
**Temporal Workflows**: 5 (Poller, EVM/UTXO/Substrate Processor, Webhook Dispatcher)  
**Temporal Activities**: 9  

---

## 2. 🔴 重大な問題 (Critical)

### 2.1 テストが一切存在しない

```
spec/ → 0 files
test/ → 0 files
```

Gemfile に `rspec-rails` と `factory_bot_rails` があるが、テストファイルがゼロ。
4,750行のビジネスロジックがテストなしで本番稼働している。

**リスク**: リファクタリング不能、リグレッション検出不可  
**推奨**: 最低限以下のテストを優先的に追加
- Activity 単体テスト (RPC mock + DB assertion)
- `decode_transfers` のイベントパース (ERC-20/721/1155 の boundary cases)
- Webhook delivery の HMAC 署名検証
- API controller の request spec

### 2.2 認証・認可が存在しない

全 API エンドポイント (チェーン設定 CRUD、インデクサー start/stop、Webhook 管理) が**認証なし**で公開。

```ruby
class ApplicationController < ActionController::API
  # 認証なし
end
```

**リスク**: 誰でもインデクサーを停止、チェーン設定を削除、RPC URL を変更可能  
**推奨**: 最低限 API Key ベースの認証 (`Authorization: Bearer <token>`) を追加

### 2.3 PostgreSQL が Temporal と application DB を共有

```yaml
# docker-compose.yml
postgres:
  image: postgres:17-alpine
  # → Temporal auto-setup も同じインスタンスを使用
```

Temporal は自身の history/visibility テーブルを大量に書き込む。application の大量 upsert と競合し、I/O ボトルネックになる。

**推奨**: Temporal 用と application 用の PostgreSQL を分離 (少なくとも別 DB、理想は別コンテナ)

### 2.4 DB コネクションプール不足

```yaml
pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
```

Worker は 7 スレッド (Task Queue ごと) を並列実行し、各スレッドが Activity 内で DB 接続を使う。
`blocks_per_batch: 10` で並列子 WF → 各 Activity が DB 接続 → 最大 70 同時接続の可能性。

**推奨**: Worker 用の `DATABASE_URL` に `?pool=25` を追加、または `RAILS_MAX_THREADS=25` を設定

---

## 3. 🟠 重要な問題 (High)

### 3.1 N+1 クエリの多発

`AssetTransfer#token_symbol`, `#formatted_amount`, `#tx_url` が毎回 `ChainConfig.find_by` と `TokenContract.find_by` を呼ぶ。
Dashboard のリスト表示で N+1 が発生。

```ruby
def token_symbol
  chain = ChainConfig.find_by(chain_id: chain_id)  # 毎回クエリ
  ...
end
```

**推奨**: 
- `belongs_to :chain_config, foreign_key: :chain_id, primary_key: :chain_id` を追加
- Dashboard/API で `includes(:chain_config)` を使用
- `ChainConfig` をインメモリキャッシュ (11件しかない)

### 3.2 `address_transfers` の全アドレス小文字比較

```ruby
scope = case sub.direction
when 'incoming' then scope.where('LOWER(to_address) = ?', addr)
```

`LOWER()` を使うと**インデックスが効かない**。`from_address` / `to_address` のインデックスは生値に対して作成されている。

**推奨**: 
- `normalize_addresses` の `before_save` で既に downcase しているので、`LOWER()` を外して直接比較
- または `citext` 型に変更

### 3.3 FetchBlockActivity の `decode_transfers` がモノリシック (260行)

`fetch_and_store` メソッドが RPC fetch + DB store + transfer decode + token enqueue を全て1メソッドで実行。
260行以上あり、テスタビリティが低い。

**推奨**: Transfer デコード部分を `TransferDecoder` サービスクラスに切り出し

### 3.4 Webhook `scan_and_enqueue` のスキャン効率

```ruby
subs.each do |sub|
  last_delivery = WebhookDelivery.where(address_subscription_id: sub.id)
                                 .order(asset_transfer_id: :desc).first
```

サブスクリプションごとに2回以上クエリ → サブスクリプション数に比例して遅くなる。

**推奨**: 
- グローバルな `last_scanned_id` を `indexer_cursors` に持たせてバッチスキャン
- または `WebhookDelivery` に composite index `(address_subscription_id, asset_transfer_id DESC)` を追加

### 3.5 `chain_native_symbol` がハードコード

`AddressTransfersController` に native symbol のハードコード。`ChainConfig.native_currency` が既にあるのに使っていない。

```ruby
def chain_native_symbol(chain_id)
  case chain_id
  when 137 then "MATIC"
  ...
end
```

**推奨**: `ChainConfig.find_by(chain_id:)&.native_currency || 'ETH'` に統一

---

## 4. 🟡 中程度の問題 (Medium)

### 4.1 Docker イメージが最適化されていない

```dockerfile
FROM ruby:3.3-slim AS base
RUN apt-get install ... build-essential ...
```

Multi-stage build を使っていない。`build-essential` が runtime イメージに含まれ、イメージサイズが不必要に大きい。

**推奨**: Builder stage と Runtime stage を分離

```dockerfile
FROM ruby:3.3-slim AS builder
RUN apt-get install build-essential libpq-dev ...
COPY Gemfile ./
RUN bundle lock && bundle install

FROM ruby:3.3-slim AS runtime
RUN apt-get install libpq5 libyaml-0-2
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .
```

### 4.2 `token_contracts` テーブルの `address` が `varchar(42)` (EVM only)

UTXO の address (bech32) は最大62文字、Substrate の SS58 は48文字。
`token_contracts.address` が `varchar(42)` 固定。

**影響**: 現在 UTXO/Substrate にトークンコントラクトはないので実害なし  
**推奨**: 将来に備え `varchar(128)` に拡張

### 4.3 Temporal Worker が全 Workflow/Activity を全 Queue に登録

```ruby
threads = task_queues.map do |queue|
  Thread.new(queue) do |q|
    worker = Temporalio::Worker.new(
      workflows: workflows,      # 5 WF 全部
      activities: activities      # 9 Activity 全部
    )
  end
end
```

例: Bitcoin chain の queue に `SubstrateBlockProcessorWorkflow` が登録されている (使われないが無駄)。

**推奨**: chain_type ごとに必要な WF/Activity のみ登録

### 4.4 `Gemfile.lock` が `.gitignore` されている

Docker 内で生成する設計だが、CI/CD やローカル開発時の再現性が低い。

**推奨**: `Gemfile.lock` は commit し、Docker では `bundle install --frozen` を使う (platform 差分は `bundle lock --add-platform` で対応)

### 4.5 `process_block_activity.rb`, `process_transaction_activity.rb`, `process_log_activity.rb` が Legacy

`fetch_and_store` に統合された後、これらの Activity はほぼ `update_cursor` しか使っていない可能性。

**推奨**: Dead code を確認し、不要な Activity は削除

### 4.6 WebhookDispatcherWorkflow の `continue-as-new` で args の渡し方が異なる

```ruby
# BlockPollerWorkflow
raise Temporalio::Workflow::ContinueAsNewError.new({ ... })

# WebhookDispatcherWorkflow  
raise Temporalio::Workflow::ContinueAsNewError.new(args: [params])
```

2つの WF で `ContinueAsNewError` の引数スタイルが違う。SDK の仕様次第でどちらかが壊れうる。

**推奨**: 統一する

---

## 5. 🟢 軽微な問題 / 改善提案 (Low)

### 5.1 Rate Limiting なし
API に rate limiting がない。大量リクエストで DB が飽和する可能性。
→ `rack-attack` gem の導入

### 5.2 ログに構造化ログがない
`Rails.logger.info("Indexed block ##{block_num}")` — 文字列ベースのログ。
→ `lograge` gem で JSON 構造化ログに

### 5.3 Health check が最小限
```ruby
get 'health', to: proc { [200, {}, ['ok']] }
```
DB 接続・Temporal 接続の確認がない。
→ `/health` で `ActiveRecord::Base.connection.active?` + Temporal ping

### 5.4 Migration ファイル名のタイムスタンプが不自然
`20260221000001` 〜 `20260224000002` — 手動で連番を割り当てている。
→ 動作に影響ないが `rails generate migration` を使う方が安全

### 5.5 `indexed_blocks.block_hash` の UNIQUE が chain 跨ぎで衝突しうる
異なるチェーンで同じ block_hash が発生する可能性は極小だが、
unique index が `block_hash` 単体 → `(chain_id, block_hash)` の方が安全。

### 5.6 Puma の設定が最小限
`workers` の設定がない (デフォルト: シングルプロセス)。
→ マルチコア環境なら `workers ENV.fetch("WEB_CONCURRENCY") { 2 }` を追加

### 5.7 `AssetTransfer.normalize_addresses` が Substrate で問題
```ruby
def normalize_addresses
  self.from_address = from_address&.downcase
```
SS58 アドレスは case-sensitive。downcase すると壊れる。

**推奨**: `chain_type` を見て EVM/UTXO のみ downcase

---

## 6. パフォーマンス分析

### 6.1 現在のボトルネック

| ボトルネック | 影響 | 対策 |
|---|---|---|
| RPC 呼び出し (2回/block) | スループット律速 | Batch RPC 活用 (済), 2-mode arch (未) |
| 単一 PostgreSQL | I/O 競合 | Temporal DB 分離 |
| DB pool: 5 | Worker 並列度制限 | pool 拡大 |
| `count_estimate` 未使用箇所 | Dashboard timeout | 全テーブルで使用 (一部済) |
| `LOWER()` 比較 | Index 無効化 | 直接比較に変更 |

### 6.2 スループット推定 (現在)

| チェーン | Block time | 現在の処理速度 | 追いつけるか |
|---|---|---|---|
| Ethereum | 12s | ~2 RPC/block, OK | ✅ 余裕あり |
| Polygon | 2s | ~2 RPC/block | ⚠️ catch-up 時にギリギリ |
| Arbitrum | 250ms | ~2 RPC/block | ❌ catch-up 不可 |
| Bitcoin | 10min | ~1 RPC/block | ✅ 余裕あり |
| Polkadot AH | 12s | ~2 RPC/block | ✅ 余裕あり |

→ **2-mode architecture (catch-up / live) が Arbitrum/Polygon で必須**

---

## 7. セキュリティ分析

| 項目 | 状態 | リスク |
|---|---|---|
| API 認証 | ❌ なし | **Critical** — 誰でもインデクサー制御可能 |
| Webhook HMAC 署名 | ✅ HMAC-SHA256 | 適切 |
| DB 資格情報 | ⚠️ `indexer:indexer` ハードコード | Docker 外から接続可能 |
| RPC URL 保護 | ⚠️ `mask_url` はリスト API のみ | show API で漏れる可能性を確認 |
| CORS | ⚠️ 設定なし | ブラウザからの API 呼び出しが制限されない |
| Input validation | ⚠️ 最小限 | `chain_id` の型チェック程度 |

---

## 8. 優先順位付きアクションプラン

### P0 (すぐやるべき)
1. **API 認証の追加** — Bearer token or API key
2. **DB コネクションプール拡大** — Worker: `pool=25`

### P1 (1週間以内)
3. **テストの追加** — Activity + transfer decode + API spec
4. **N+1 クエリ修正** — `ChainConfig` キャッシュ + `includes`
5. **`LOWER()` 除去** — webhook scan + address_transfers
6. **2-mode architecture 実装** — Arbitrum/Polygon catch-up

### P2 (2週間以内)
7. **Temporal DB 分離**
8. **Docker multi-stage build**
9. **SS58 アドレス downcase 問題の修正**
10. **Legacy Activity の整理** (dead code 除去)

### P3 (余裕があれば)
11. Rate limiting (`rack-attack`)
12. 構造化ログ (`lograge`)
13. Health check の強化
14. Worker の WF/Activity 登録を chain_type ごとに分離

---

## 9. 総評

**よくできている点:**
- 3チェーンタイプ (EVM/UTXO/Substrate) の統一アーキテクチャ
- Temporal ベストプラクティスの適用 (heartbeat, retry, per-chain queue)
- DB-mediated data passing で gRPC 4MB 制限を回避
- Webhook システムの設計 (HMAC 署名, 指数バックオフ, auto-disable)
- `count_estimate` による大テーブルのカウント高速化

**改善が必要な点:**
- テストゼロ、認証ゼロ — プロダクション品質にはまだ遠い
- Fast chain (Arbitrum 250ms) への対応が未実装
- DB/Docker の構成がプロトタイプ寄り

**成熟度**: PoC → α段階。機能は揃っているが、品質・セキュリティ・テストの層が足りない。
