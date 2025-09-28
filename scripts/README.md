# Qlick Ethers.js Scripts

This directory contains ethers.js scripts that replicate all the `cast` commands mentioned in the Qlick documentation for interacting with Quantum Markets on Unichain Sepolia.

## Setup

1. **Install dependencies:**
   ```bash
   cd scripts
   npm install
   ```

2. **Configure environment:**
   Create a `.env` file in the project root with your private key:
   ```bash
   # In the root directory (not scripts/)
   echo "PRIVATE_KEY=your_private_key_here" > .env
   echo "RPC_URL=https://sepolia.unichain.org" >> .env
   ```

3. **Ensure you have testnet ETH:**
   - Get Unichain Sepolia ETH from: https://faucet.unichain.org/
   - Your wallet needs ETH for gas fees

## Usage

The script supports two main flows:

### Basic Flow
Replicates the basic 7-step flow from the documentation:
```bash
npm run basic
# or
node qlick-ethers.js basic
```

**Steps executed:**
1. Deploy fresh demo tokens (QT0, QT1) with unique addresses
2. Create fresh pool and add liquidity (with updated parameters)
3. Create fresh decision via QuantumMarketManager (timestamp-based)
4. Create fresh proposal to register new pool with new decision
5. Execute a demo swap on the registered pool
6. Settle fresh decision with winning proposal

**Note:** Each run creates completely fresh tokens, pools, decisions, and proposals to avoid conflicts with previous runs. This ensures a clean state every time.

### Extended Market Flow
Creates 3 separate fresh markets with independent decisions:
```bash
npm run extended
# or
node qlick-ethers.js extended
```

**Steps executed:**
1. Check/set orchestrator as factory (graceful if already set)
2. Create 3 fresh markets, each with:
   - Fresh tokens (unique addresses)
   - Fresh pool with liquidity
   - Fresh decision (timestamp-based)
   - Fresh proposal (links pool to decision)
3. Execute demo trading on the last pool
4. Settle all 3 decisions with their respective proposals

**Note:** This demonstrates multiple independent quantum markets running simultaneously, each with their own fresh state.

## Configuration

All contract addresses and parameters are configured in the `CONFIG` object at the top of `qlick-ethers.js`:

```javascript
const CONFIG = {
    // Network
    RPC_URL: 'https://sepolia.unichain.org',
    
    // Qlick contracts
    QUANTUM_MARKET_MANAGER: '0xBf945e3f549ceb6cA4907161679f148F48af09cC',
    QUANTUM_MARKET_HOOK: '0x19A4a8ddCBB74B33e410CE2E27833e8c42FC80c0',
    QLICK_ORCHESTRATOR: '0x641eCbB155b8589120005dE67e7aBF524034EA5B',
    
    // Pool parameters
    FEE: 3000,
    TICK_SPACING: 60,
    SQRT_PRICE_X96: '79228162514264337593543950336',
    LIQUIDITY_DESIRED: ethers.parseEther('100'),
    
    // Trading amounts
    MINT_AMOUNT: ethers.parseEther('1000000'),
    SWAP_AMOUNT: ethers.parseEther('1'),
};
```

## Cast Command Equivalents

| Cast Command | Ethers.js Equivalent |
|--------------|---------------------|
| `cast send <contract> "function()" <args>` | `contract.functionName(args)` |
| `cast call <contract> "function()(type)"` | `contract.functionName()` |
| `cast keccak "string"` | `ethers.keccak256(ethers.toUtf8Bytes("string"))` |
| `cast wallet address` | `wallet.address` |

## Contract ABIs

The script includes minimal ABIs for the required functions. If you need additional functions, add them to the respective ABI arrays:

- `ORCHESTRATOR_ABI`: Functions for the QlickOrchestrator contract
- `QUANTUM_MARKET_MANAGER_ABI`: Functions for the QuantumMarketManager contract

## Error Handling

The script includes comprehensive error handling:
- Transaction confirmation with gas usage reporting
- Detailed logging for each step
- Graceful error messages with context

## Troubleshooting

**Common issues:**

1. **"insufficient funds"**: Ensure your wallet has enough ETH for gas fees
2. **"nonce too low"**: Wait a moment between transactions or restart the script
3. **"execution reverted: set"**: Factory already set from previous run. The script handles this gracefully.
4. **"execution reverted"**: Check that contracts are deployed and addresses are correct
5. **"network error"**: Verify RPC URL is accessible
6. **Function signature mismatch**: Make sure the contract ABIs match the deployed contracts

**✅ Status**: The basic flow is now working perfectly with the fresh market approach!

**Debug mode:**
Add more detailed logging by modifying the `waitForTransaction` method or adding console.log statements.

## Contract Addresses (Unichain Sepolia)

**Core V4:**
- PoolManager: `0x00B036B58a818B1BC34d502D3fE730Db729e62AC`
- PositionManager: `0xf969Aee60879C54bAAed9F3eD26147Db216Fd664`
- V4 Router: `0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba`

**Qlick:**
- QuantumMarketManager: `0xBf945e3f549ceb6cA4907161679f148F48af09cC`
- QuantumMarketHook: `0x19A4a8ddCBB74B33e410CE2E27833e8c42FC80c0`
- QlickOrchestrator: `0x641eCbB155b8589120005dE67e7aBF524034EA5B`

## License

MIT
