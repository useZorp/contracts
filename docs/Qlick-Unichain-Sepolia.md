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

