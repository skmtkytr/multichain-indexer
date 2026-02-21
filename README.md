# EVM Indexer

Ethereum/EVM blockchain indexer built with **Ruby on Rails** + **Temporal**.

## Architecture

```
┌─────────────┐     ┌──────────────────┐     ┌──────────┐
│  EVM Chain   │◄────│  Temporal Worker  │────►│ Postgres │
│  (RPC Node)  │     │                  │     │          │
└─────────────┘     └──────────────────┘     └──────────┘
                           ▲                       ▲
                           │                       │
                    ┌──────┴───────┐        ┌──────┴──────┐
                    │   Temporal   │        │  Rails API  │
                    │   Server     │        │  (web)      │
                    └──────────────┘        └─────────────┘
```

### Temporal Workflows

- **BlockPollerWorkflow** - Long-running workflow that continuously polls for new blocks. Uses `continue-as-new` to keep history bounded.
- **BlockProcessorWorkflow** - Processes a single block: fetches full data, stores block/transactions/logs with retry policies.

### Activities

- `FetchBlockActivity` - RPC calls to the chain
- `ProcessBlockActivity` - Stores block data + updates cursor
- `ProcessTransactionActivity` - Stores transaction + receipt data
- `ProcessLogActivity` - Stores event logs for a block

## Setup

```bash
cp .env.example .env
# Edit .env with your RPC URL

docker compose up --build
docker compose exec web bin/rails db:create db:migrate
```

## Usage

```bash
# Start indexing (defaults to chain_id=1, latest block)
curl -X POST http://localhost:3000/api/v1/indexer/start

# Start from specific block
curl -X POST http://localhost:3000/api/v1/indexer/start \
  -H "Content-Type: application/json" \
  -d '{"chain_id": 1, "start_block": 19000000}'

# Check status
curl http://localhost:3000/api/v1/indexer/status?chain_id=1

# Stop indexing
curl -X POST http://localhost:3000/api/v1/indexer/stop?chain_id=1

# Query indexed data
curl http://localhost:3000/api/v1/blocks?limit=10
curl http://localhost:3000/api/v1/blocks/19000000
curl http://localhost:3000/api/v1/transactions?from=0x1234...
curl http://localhost:3000/api/v1/logs?address=0xdead...&topic0=0xddf252...
```

## Temporal UI

Open http://localhost:8080 to monitor workflows.

## Multi-chain

Set `chain_id` parameter to index different EVM chains:
- `1` = Ethereum Mainnet
- `137` = Polygon
- `42161` = Arbitrum
- `10` = Optimism
- `8453` = Base

Each chain runs its own independent `BlockPollerWorkflow`.
