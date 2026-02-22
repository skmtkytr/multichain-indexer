# Multichain Indexer

A unified blockchain indexer supporting **EVM**, **UTXO (Bitcoin forks)**, and **Substrate (Polkadot)** chains. Built with **Ruby on Rails** + **Temporal**.

## Supported Chain Types

| Type | Chains | Data Source |
|------|--------|-------------|
| **EVM** | Ethereum, Polygon, Arbitrum, Optimism, Base, BSC, etc. | JSON-RPC (`eth_getBlockByNumber`, `eth_getBlockReceipts`) |
| **UTXO** | Bitcoin, Litecoin, Dogecoin, Bitcoin Cash | JSON-RPC (`getblock` verbosity=2) |
| **Substrate** | Polkadot Asset Hub | Sidecar REST API + Substrate JSON-RPC |

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌──────────┐
│  Blockchain  │◄────│  Temporal Worker  │────►│ Postgres │
│  (RPC/API)   │     │                  │     │          │
└─────────────┘     └──────────────────┘     └──────────┘
                           ▲                       ▲
                           │                       │
                    ┌──────┴───────┐        ┌──────┴──────┐
                    │   Temporal   │        │  Rails API  │
                    │   Server     │        │  + Dashboard│
                    └──────────────┘        └─────────────┘
```

### Workflows

- **BlockPollerWorkflow** — Polls for new blocks, dispatches to chain-type-specific processor. Uses `continue-as-new` every 100 blocks.
- **BlockProcessorWorkflow** (EVM) — Fetch block + receipts → decode transfers (ERC-20/721/1155, native, internal, withdrawals)
- **UtxoBlockProcessorWorkflow** — Fetch block → parse inputs/outputs → resolve UTXOs → asset transfers
- **SubstrateBlockProcessorWorkflow** — Fetch extrinsics/events via Sidecar → decode transfers (DOT, Assets, Foreign Assets, NFTs)

### Key Features

- **Asset transfer tracing** — Track token movements per transaction (from, to, amount, type)
- **Multi-endpoint RPC failover** — Priority-based fallback across multiple RPC endpoints
- **Dashboard UI** — Real-time stats, chain management, address lookup, transfer explorer
- **DB-managed chain configs** — Add/edit chains from the dashboard, no restart required
- **Trace support** (EVM) — `debug_traceBlockByNumber` / `trace_block` for internal transactions
- **MWEB/privacy support** (UTXO) — Peg-in/peg-out boundary tracking for Litecoin MWEB

## Setup

```bash
cp .env.example .env
docker compose up --build
docker compose exec web bin/rails db:create db:migrate db:seed
```

## Usage

```bash
# Dashboard
open http://localhost:3000

# Start indexing
curl -X POST http://localhost:3000/api/v1/indexer/start \
  -H "Content-Type: application/json" \
  -d '{"chain_id": 1}'

# Start from specific block
curl -X POST http://localhost:3000/api/v1/indexer/start \
  -H "Content-Type: application/json" \
  -d '{"chain_id": 1, "start_block": 19000000}'

# Check status
curl http://localhost:3000/api/v1/indexer/status?chain_id=1

# Stop indexing
curl -X POST http://localhost:3000/api/v1/indexer/stop?chain_id=1

# Query data
curl http://localhost:3000/api/v1/blocks?chain_id=1&limit=10
curl http://localhost:3000/api/v1/asset_transfers?chain_id=1&limit=20
curl http://localhost:3000/api/v1/address_transfers?addresses=0x1234...&chain_id=1
```

## Preconfigured Chains

| Chain | ID | Type | Status |
|-------|----|------|--------|
| Ethereum | 1 | EVM | Enabled |
| Sepolia | 11155111 | EVM | Disabled |
| Polygon | 137 | EVM | Disabled |
| Arbitrum | 42161 | EVM | Disabled |
| Optimism | 10 | EVM | Disabled |
| Base | 8453 | EVM | Disabled |
| Bitcoin | 800000000 | UTXO | Disabled |
| Litecoin | 800000002 | UTXO | Disabled |
| Dogecoin | 800000003 | UTXO | Disabled |
| Bitcoin Cash | 800000145 | UTXO | Disabled |
| Polkadot Asset Hub | 900000001 | Substrate | Disabled |

## Temporal UI

http://localhost:8080

## Tech Stack

- **Ruby on Rails 8.1** (API mode + inline dashboard)
- **Temporal** (workflow orchestration, `temporalio` gem)
- **PostgreSQL** (unlimited precision `numeric` for wei/satoshi values)
- **Docker Compose** (all services)
