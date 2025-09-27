# Qlick — Quantum Markets on Uniswap v4

Qlick is a reference implementation of Quantum Markets built on Uniswap v4 hooks. It lets traders provision shared trading credit across many competing proposal markets for a single decision, enabling capital-efficient evaluation of large option sets. The design is inspired by Paradigm's research post on Quantum Markets and uses Uniswap v4's hook system to wire proposal-specific markets to a shared decision manager.

References:
- Research: [Quantum Markets (Paradigm)](https://www.paradigm.xyz/2025/06/quantum-markets)

### Get Started

This repository is a Foundry project that compiles, tests, and deploys the Qlick contracts. You can run unit tests locally and (optionally) run end-to-end tests using the v4 periphery helpers.

What's inside:
- `src/QuantumMarketManager.sol`: Decision registry. Tracks decisions, proposal registrations, and settlement.
- `src/QuantumMarketHook.sol`: Uniswap v4 hook that observes swaps and tracks proposal-market activity.
- `src/QuantumCreditVault.sol`: Simple ETH-backed vault that mints non-transferable shared credits.
- `src/QuantumCredits.sol`: Minimal non-transferable credit token used by the vault.
- `test/QuantumMarkets.t.sol`: E2E-style test using v4 periphery harnesses (may require correct artifact wiring for runtime deployment via address flags).


### Qlick specifics

- Project name: Qlick
- Core mechanism: Deposit once to `QuantumCreditVault`, receive credits you can notionally use across all proposal markets for the same decision.
- Decisions and proposals are tracked in `QuantumMarketManager`. Each proposal is represented by a Uniswap v4 `PoolKey` wired to the shared `QuantumMarketHook`.
- The hook records simple notional trade volume per pool as a stand-in for market signals; settlement is delegated to the manager (in this demo: by keeper input).




