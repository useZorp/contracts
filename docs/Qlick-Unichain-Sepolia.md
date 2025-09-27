# Qlick — Quantum Markets on Unichain Sepolia (1301)

This document summarizes the deployed contracts, the end-to-end flow executed on Unichain Sepolia, and commands to reproduce.

## Overview

Qlick implements Quantum Markets using Uniswap v4 hooks. Traders deposit once and receive shared credits to trade across multiple proposal markets for the same decision. Only the winning proposal’s PnL persists; losing proposals effectively no-op at settlement.

References:
- https://www.paradigm.xyz/2025/06/quantum-markets
- https://github.com/Sofianel5/quantum-markets/tree/master

## Network

- Chain: Unichain Sepolia (chainId 1301)
- RPC: https://sepolia.unichain.org

## Core Addresses

- PoolManager: 0x00B036B58a818B1BC34d502D3fE730Db729e62AC
- PositionManager: 0xf969Aee60879C54bAAed9F3eD26147Db216Fd664
- V4 Router: 0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba
- Permit2: 0x000000000022D473030F116dDEE9F6B43aC78BA3

## Qlick Contracts (latest)

- QuantumMarketManager: 0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7
- QuantumMarketHook: 0xBEFc843B8CA25F0EDcA88D25B0cCfF1d3D8f40c0
- QlickOrchestrator: 0x641eCbB155b8589120005dE67e7aBF524034EA5B

Demo tokens (minted by orchestrator):
- QT0: 0xb6ce7cf82208446b00340f53e4ac6ee3b9d5b3fc
- QT1: 0x3f756a8c980038ae31147249643c2b4900a96c2d

## End-to-End Flow

Setup:
```bash
export RPC=https://sepolia.unichain.org
export PK=<deployer_private_key>
```

1) Deploy Qlick core
```bash
forge script script/00_DeployQlick.s.sol \
  --rpc-url $RPC \
  --private-key $PK \
  --broadcast
```
Outputs:
- QM: 0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7
- Hook: 0xBEFc843B8CA25F0EDcA88D25B0cCfF1d3D8f40c0

2) Deploy orchestrator
```bash
forge script script/05_DeployOrchestrator.s.sol \
  --rpc-url $RPC \
  --private-key $PK \
  --broadcast
```
Output: 0x641eCbB155b8589120005dE67e7aBF524034EA5B

3) Deposit once (mint demo tokens)
```bash
cast send 0x641eCbB155b8589120005dE67e7aBF524034EA5B \
  "deployTokens(uint256)" 1000000000000000000000000 \
  --rpc-url $RPC --private-key $PK
```

4) Create pool + add liquidity (shared hook)
```bash
cast send 0x641eCbB155b8589120005dE67e7aBF524034EA5B \
  "createPoolAndAddLiquidity(address,uint24,int24,uint160,uint128)" \
  0xBEFc843B8CA25F0EDcA88D25B0cCfF1d3D8f40c0 3000 60 79228162514264337593543950336 100000000000000000000 \
  --rpc-url $RPC --private-key $PK
```

5) Register decision + proposals
```bash
cast send 0x641eCbB155b8589120005dE67e7aBF524034EA5B \
  "registerDecision(address)" 0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7 \
  --rpc-url $RPC --private-key $PK
```
To add more proposals: call `QuantumMarketManager.createProposal(decisionId, proposalId, name, PoolKey)` per proposal.

6) Trade on a proposal
```bash
cast send 0x641eCbB155b8589120005dE67e7aBF524034EA5B \
  "swapOnPool(bool,uint256)" true 1000000000000000000 \
  --rpc-url $RPC --private-key $PK
```

7) Settle decision (pick winner)
```bash
cast keccak "proposal-2"
# use the hash as winningProposalId
cast send 0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7 \
  "settle(uint256,bytes32)" 1 0x3dbd69b0147bf12e8d12f2b722a8a3899f83ed63230cb1a440275b51fc89a526 \
  --rpc-url $RPC --private-key $PK
```

## UI Flow (at a glance)
- Create Market → `createDecision`
- Add Proposals (4+) → init pools (shared hook) → `createProposal`
- Deposit → `QuantumCreditVault.deposit`
- Trade per Proposal → router swaps on each `PoolKey`
- Settle → `settle(decisionId, winningProposalId)`


## Market Model (Qlick)
- Decision markets consist of multiple proposals (outcomes). Liquidity is provided to per-proposal pools that all share the same hook.
- Traders deposit once into a market token budget and receive credits (vUSD + YES/NO tokens per proposal). Only the selected/winning proposal realizes PnL; others no-op on settlement.
- For deployment size and simplicity, pool deployment and periphery interactions live in an orchestrator; the manager remains lean and authoritative over market lifecycle/state.


## Core Contracts & Functions

### QuantumMarketManager (on-chain state + policy)
- Decisions (demo/simple):
  - `createDecision(string metadata) → uint256 decisionId`
  - `createProposal(uint256 decisionId, bytes32 proposalId, string metadata, PoolKey poolKey)`
  - `settle(uint256 decisionId, bytes32 winningProposalId)`
- Markets (factory-managed):
  - `setFactory(address f)` (one-time)
  - `createMarket(address creator, address marketToken, address resolver, uint256 minDeposit, uint256 deadline, string title) → uint256 marketId` (onlyFactory)
  - `depositToMarket(address depositor, uint256 marketId, uint256 amount)` (onlyFactory)
  - `createProposalForMarket(uint256 marketId, address creator, address vUSD, address yesToken, address noToken, bytes data) → uint256 proposalId` (onlyFactory)
  - `setProposalPools(uint256 proposalId, PoolKey yesKey, PoolKey noKey)`
  - `acceptProposal(uint256 marketId, uint256 proposalId)`
  - `resolveMarket(uint256 marketId, bool yesOrNo)`
  - `redeemRewards(uint256 marketId, address user)`
- Hook integration:
  - `validateSwap(PoolKey key)` (reverts if pool not registered or market settled)
  - `updatePostSwap(PoolKey key, int24 avgTick)` (stores last avg tick per pool)

Storage (selected):
- `markets(uint256) → MarketConfig` with fields: `id, createdAt, minDeposit, deadline, creator, marketToken, resolver, status, title`
- `proposals(uint256) → ProposalConfig` with fields: `id, marketId, createdAt, creator, tokens{vUSD,yesToken,noToken}, yesPoolKey, noPoolKey, data`
- `poolToProposal(PoolId) → uint256`, `poolToDecision(PoolId) → uint256`, `lastAvgTick(PoolId) → int24`
- `deposits(marketId, user) → uint256`, `proposalDepositClaims(marketId, user) → uint256`

Notes:
- `marketToken` is any ERC20 used for deposits and settlement payouts (e.g., USDC, WETH). If a user wants to deposit native ETH, wrap to WETH and approve the factory to transfer before calling `depositToMarket`.

### QuantumMarketHook (shared pool hook)
- Permissions: `BEFORE_SWAP | AFTER_SWAP` encoded in the address (mined via CREATE2).
- `initialize(address market)` (one-time) to register the manager.
- `_beforeSwap` → calls `manager.validateSwap(poolKey)`.
- `_afterSwap` → computes ~30s rolling TWAP from `poolManager.extsloadSlot0` and calls `manager.updatePostSwap(poolKey, avgTick)`.

### Tokens
- `VUSD` (ERC20Mintable, ERC20Burnable) – virtual quote token used for credits and PnL realization.
- `DecisionToken` (YES/NO, ERC20Mintable, ERC20Burnable) – per-proposal outcome token.

### QlickOrchestrator (periphery helper)
- `deployTokens(uint256 mintAmount)` – deploys demo `QT0`, `QT1` and mints budget to itself.
- `createPoolAndAddLiquidity(address hook, uint24 fee, int24 spacing, uint160 sqrtPriceX96, uint128 liquidityDesired)` – initializes a pool with shared hook and adds liquidity via PositionManager.
- Decision demo:
  - `registerDecision(QuantumMarketManager qm)` – creates a decision and two proposals using the last pool key.
- Market flow:
  - `createMarket(QuantumMarketManager qm, address marketToken, address resolver, uint256 minDeposit, uint256 deadline, string title)` – sets factory if unset and creates a market.
  - `createProposalWithDualPools(QuantumMarketManager qm, address hook, uint24 fee, int24 spacing, uint160 sqrtPriceX96, uint128 liquidityDesired)` – mints vUSD/YES/NO, initializes YES/VUSD and NO/VUSD pools, adds liquidity, and wires them to the manager via `setProposalPools`.
  - `swapOnPool(bool zeroForOne, uint256 amountIn)` – executes a swap on `lastPoolKey` using the periphery router.


## Hook Permissions (address-encoded)
- The hook address must set the exact bits for implemented callbacks. For Qlick: BEFORE_SWAP and AFTER_SWAP.
- On production networks, mine the salt via `v4-periphery/HookMiner.find` and deploy with CREATE2.


## Cast User Flow (3 proposals example)
This sequence creates a market, adds three proposals (each with dual pools + liquidity), trades, accepts, resolves, and redeems.

Setup
```bash
export RPC=https://unichain-sepolia.drpc.org
export PK=<your_private_key>
export QM=0x6CD1EfcA0D1DF8BB55c45fEF2D1F4962103B00F7
export ORCH=0x641eCbB155b8589120005dE67e7aBF524034EA5B
export HOOK=0xBEFc843B8CA25F0EDcA88D25B0cCfF1d3D8f40c0
```

1) Ensure factory is set (one-time)
```bash
cast send $QM "setFactory(address)" $ORCH --rpc-url $RPC --private-key $PK
```

2) Choose market token and mint demo budgets
```bash
cast send $ORCH "deployTokens(uint256)" 1000000000000000000000000 --rpc-url $RPC --private-key $PK
MTK=$(cast call $ORCH "token0()(address)" --rpc-url $RPC); echo MarketToken=$MTK
```

3) Create market (minDeposit=0)
```bash
DEADLINE=$(($(date +%s)+86400))
cast send $ORCH "createMarket(address,address,uint256,uint256,string)" $QM $MTK 0 $DEADLINE "Fruit Market" --rpc-url $RPC --private-key $PK
MID=$(cast call $ORCH "lastMarketId()(uint256)" --rpc-url $RPC); echo MID=$MID
```

4) Add 3 proposals with dual pools
```bash
SQRT=79228162514264337593543950336
LIQ=100000000000000000000
cast send $ORCH "createProposalWithDualPools(address,address,uint24,int24,uint160,uint128)" $QM $HOOK 3000 60 $SQRT $LIQ --rpc-url $RPC --private-key $PK
cast send $ORCH "createProposalWithDualPools(address,address,uint24,int24,uint160,uint128)" $QM $HOOK 3000 60 $SQRT $LIQ --rpc-url $RPC --private-key $PK
cast send $ORCH "createProposalWithDualPools(address,address,uint24,int24,uint160,uint128)" $QM $HOOK 3000 60 $SQRT $LIQ --rpc-url $RPC --private-key $PK
PID=$(cast call $QM "nextProposalId()(uint256)" --rpc-url $RPC); echo "nextProposalId="$PID
```

5) Trade on the last created pool (demo)
```bash
cast send $ORCH "swapOnPool(bool,uint256)" true 1000000000000000000 --rpc-url $RPC --private-key $PK
```

6) Accept a proposal for the market
```bash
# Accept the latest proposalId - 1 (since nextProposalId points to the next)
ACC=$(( $(cast call $QM "nextProposalId()(uint256)" --rpc-url $RPC) - 1 ))
cast send $QM "acceptProposal(uint256,uint256)" $MID $ACC --rpc-url $RPC --private-key $PK
```

7) Resolve and redeem
```bash
cast send $QM "resolveMarket(uint256,bool)" $MID true --rpc-url $RPC --private-key $PK
EOA=$(cast wallet address --private-key $PK)
cast send $QM "redeemRewards(uint256,address)" $MID $EOA --rpc-url $RPC --private-key $PK
```

Notes
- Deposits: For a non-zero `minDeposit`, call the factory’s `depositToMarket` pathway with an ERC20 `marketToken` approved. To use native ETH, wrap to WETH and set `marketToken=WETH`.
- Quotes: Use V4 `Quoter` to preview swap deltas by simulating `quoteExactInputSingle` with the specific `PoolKey` and amount.
- Pool discovery: listen to `PoolCreated` from `PoolManager` or track `PoolKey`/`PoolId` from orchestrator events.

