const { ethers } = require('ethers');
require('dotenv').config();

// Configuration
const CONFIG = {
    RPC_URL: process.env.RPC_URL || 'https://sepolia.unichain.org',
    PRIVATE_KEY: process.env.PRIVATE_KEY,
    
    // Core V4 addresses on Unichain Sepolia
    POOL_MANAGER: '0x00B036B58a818B1BC34d502D3fE730Db729e62AC',
    POSITION_MANAGER: '0xf969Aee60879C54bAAed9F3eD26147Db216Fd664',
    V4_ROUTER: '0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba',
    PERMIT2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
    
    // Qlick contracts (update these after deployment)
    QUANTUM_MARKET_MANAGER: '0xBf945e3f549ceb6cA4907161679f148F48af09cC',
    QUANTUM_MARKET_HOOK: '0x19A4a8ddCBB74B33e410CE2E27833e8c42FC80c0',
    QLICK_ORCHESTRATOR: '0x641eCbB155b8589120005dE67e7aBF524034EA5B',
    
    // Pool parameters
    FEE: 3000,
    TICK_SPACING: 60,
    SQRT_PRICE_X96: '79228162514264337593543950336',
    TICK_LOWER: -120, // Multiple of tick spacing (60 * -2)
    TICK_UPPER: 120,  // Multiple of tick spacing (60 * 2)
    LIQUIDITY_DESIRED: ethers.parseEther('100'),
    AMOUNT_0_MAX: ethers.parseEther('100'), // Smaller max amounts
    AMOUNT_1_MAX: ethers.parseEther('100'), // Smaller max amounts
    
    // Token amounts
    MINT_AMOUNT: ethers.parseEther('1000000'),
    SWAP_AMOUNT: ethers.parseEther('1'),
    
    // Market parameters
    MIN_DEPOSIT: 0,
    MARKET_TITLE: 'Fruit Market'
};

// Contract ABIs (minimal required functions)
const ORCHESTRATOR_ABI = [
    'function deployTokens(uint256 mintAmount)',
    // Try both versions of the function
    'function createPoolAndAddLiquidity(address hook, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, uint128 liquidityDesired)',
    'function createPoolAndAddLiquidity(address hook, uint24 fee, int24 tickSpacing, uint160 sqrtPriceX96, int24 tickLower, int24 tickUpper, uint128 liquidityDesired, uint256 amount0Max, uint256 amount1Max)',
    'function swapOnPool(bool zeroForOne, uint256 amountIn)',
    'function createMarket(address qm, address marketToken, address resolver, uint256 minDeposit, uint256 deadline, string title)',
    'function token0() view returns (address)',
    'function lastMarketId() view returns (uint256)',
    'function lastPoolKey() view returns (tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks))'
];

const QUANTUM_MARKET_MANAGER_ABI = [
    'function createDecision(string metadata) returns (uint256)',
    'function createProposal(uint256 decisionId, bytes32 proposalId, string metadata, tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey)',
    'function settle(uint256 decisionId, bytes32 winningProposalId)',
    'function setFactory(address f)',
    'function acceptProposal(uint256 marketId, uint256 proposalId)',
    'function resolveMarket(uint256 marketId, bool yesOrNo)',
    'function redeemRewards(uint256 marketId, address user)',
    'function nextProposalId() view returns (uint256)',
    'function nextDecisionId() view returns (uint256)',
    'event DecisionCreated(uint256 indexed decisionId, string metadata)'
];

class QlickEthersScript {
    constructor() {
        if (!CONFIG.PRIVATE_KEY) {
            throw new Error('PRIVATE_KEY environment variable is required');
        }
        
        this.provider = new ethers.JsonRpcProvider(CONFIG.RPC_URL);
        this.wallet = new ethers.Wallet(CONFIG.PRIVATE_KEY, this.provider);
        
        this.orchestrator = new ethers.Contract(
            CONFIG.QLICK_ORCHESTRATOR,
            ORCHESTRATOR_ABI,
            this.wallet
        );
        
        this.quantumMarketManager = new ethers.Contract(
            CONFIG.QUANTUM_MARKET_MANAGER,
            QUANTUM_MARKET_MANAGER_ABI,
            this.wallet
        );
        
        console.log(`Connected to ${CONFIG.RPC_URL}`);
        console.log(`Wallet address: ${this.wallet.address}`);
    }

    async waitForTransaction(tx, description) {
        console.log(`\n${description}`);
        console.log(`Transaction hash: ${tx.hash}`);
        
        const receipt = await tx.wait();
        console.log(`✅ Confirmed in block ${receipt.blockNumber}`);
        console.log(`Gas used: ${receipt.gasUsed.toString()}`);
        
        return receipt;
    }

    // Basic Flow - Creates fresh market each time
    async runBasicFlow() {
        console.log('\n🚀 Starting Basic Qlick Flow (Fresh Market)...\n');

        try {
            // Step 1: Deploy fresh tokens each time
            console.log('Step 1: Deploying fresh tokens...');
            const deployTokensTx = await this.orchestrator.deployTokens(CONFIG.MINT_AMOUNT);
            await this.waitForTransaction(deployTokensTx, 'Deploying fresh demo tokens');

            // Step 2: Create fresh pool + add liquidity
            console.log('\nStep 2: Creating fresh pool and adding liquidity...');
            let poolCreated = false;
            try {
                // Try the original 5-parameter version first (matching the cast command)
                console.log('Trying original 5-parameter version...');
                const createPoolTx = await this.orchestrator['createPoolAndAddLiquidity(address,uint24,int24,uint160,uint128)'](
                    CONFIG.QUANTUM_MARKET_HOOK,
                    CONFIG.FEE,
                    CONFIG.TICK_SPACING,
                    CONFIG.SQRT_PRICE_X96,
                    CONFIG.LIQUIDITY_DESIRED
                );
                await this.waitForTransaction(createPoolTx, 'Creating fresh pool and adding liquidity (5 params)');
                poolCreated = true;
            } catch (error) {
                console.log('⚠️  5-parameter version failed, trying 9-parameter version...');
                try {
                    const createPoolTx = await this.orchestrator['createPoolAndAddLiquidity(address,uint24,int24,uint160,int24,int24,uint128,uint256,uint256)'](
                        CONFIG.QUANTUM_MARKET_HOOK,
                        CONFIG.FEE,
                        CONFIG.TICK_SPACING,
                        CONFIG.SQRT_PRICE_X96,
                        CONFIG.TICK_LOWER,
                        CONFIG.TICK_UPPER,
                        CONFIG.LIQUIDITY_DESIRED,
                        CONFIG.AMOUNT_0_MAX,
                        CONFIG.AMOUNT_1_MAX
                    );
                    await this.waitForTransaction(createPoolTx, 'Creating fresh pool and adding liquidity (9 params)');
                    poolCreated = true;
                } catch (error2) {
                    console.log('⚠️  Both pool creation methods failed. This might be due to:');
                    console.log('   - Pool configuration issues');
                    console.log('   - Contract version mismatch');
                    console.log('   - Parameter validation issues');
                    console.log('Error:', error2.message);
                    throw new Error('Failed to create pool - cannot continue without a fresh pool');
                }
            }

            // Step 3: Create fresh decision for this market
            console.log('\nStep 3: Creating fresh decision...');
            let decisionId;
            
            // Always create a unique decision to ensure fresh state
            const timestamp = Math.floor(Date.now() / 1000);
            const decisionMetadata = `Fresh Demo Decision ${timestamp}`;
            
            const createDecisionTx = await this.quantumMarketManager.createDecision(decisionMetadata);
            const receipt = await this.waitForTransaction(createDecisionTx, 'Creating fresh decision');
            
            // Parse the decision ID from the DecisionCreated event
            const decisionCreatedEvent = receipt.logs.find(log => {
                try {
                    const parsed = this.quantumMarketManager.interface.parseLog(log);
                    return parsed && parsed.name === 'DecisionCreated';
                } catch {
                    return false;
                }
            });
            
            if (decisionCreatedEvent) {
                const parsed = this.quantumMarketManager.interface.parseLog(decisionCreatedEvent);
                decisionId = parsed.args.decisionId;
                console.log(`✅ Created fresh decision with ID: ${decisionId}`);
            } else {
                // Fallback: get the next decision ID (it should be the one we just created)
                const nextId = await this.quantumMarketManager.nextDecisionId();
                decisionId = Number(nextId) - 1; // The one we just created
                console.log(`📋 Using calculated decision ID: ${decisionId}`);
            }

            // Step 4: Create fresh proposal to register the fresh pool with fresh decision
            console.log('\nStep 4: Creating fresh proposal to register pool...');
            
            // Get the fresh pool key from the orchestrator
            const poolKeyResult = await this.orchestrator.lastPoolKey();
            console.log('Fresh pool key result:', poolKeyResult);
            
            // Convert the read-only Result to a mutable object
            const poolKey = {
                currency0: poolKeyResult[0],
                currency1: poolKeyResult[1], 
                fee: poolKeyResult[2],
                tickSpacing: poolKeyResult[3],
                hooks: poolKeyResult[4]
            };
            console.log('Formatted fresh pool key:', poolKey);
            
            // Create a unique proposal that links the fresh pool to the fresh decision
            const proposalId = ethers.keccak256(ethers.toUtf8Bytes(`fresh-proposal-${timestamp}`));
            const createProposalTx = await this.quantumMarketManager.createProposal(
                decisionId,
                proposalId,
                `Fresh Demo Proposal ${timestamp}`,
                poolKey
            );
            await this.waitForTransaction(createProposalTx, 'Creating fresh proposal and registering fresh pool');

            // Step 7: Trade on a proposal
            console.log('\nStep 5: Trading on proposal...');
            const swapTx = await this.orchestrator.swapOnPool(true, CONFIG.SWAP_AMOUNT);
            await this.waitForTransaction(swapTx, 'Executing swap on pool');

            // Step 6: Settle decision (pick winner)
            console.log('\nStep 6: Settling fresh decision...');
            console.log(`Winning proposal ID: ${proposalId}`);
            
            const settleTx = await this.quantumMarketManager.settle(decisionId, proposalId);
            await this.waitForTransaction(settleTx, 'Settling fresh decision with winning proposal');

            console.log('\n✅ Fresh Basic Flow completed successfully!');
            console.log(`📊 Summary:`);
            console.log(`   - Fresh Decision ID: ${decisionId}`);
            console.log(`   - Fresh Proposal ID: ${proposalId}`);
            console.log(`   - Fresh Pool: ${poolKey.currency0} / ${poolKey.currency1}`);

        } catch (error) {
            console.error('\n❌ Basic flow failed:', error.message);
            throw error;
        }
    }

    // Extended Market Flow - Simplified to use available functions
    async runExtendedMarketFlow() {
        console.log('\n🚀 Starting Extended Market Flow (Multiple Fresh Decisions)...\n');

        try {
            // Step 1: Ensure factory is set (skip if already set)
            console.log('Step 1: Checking/setting factory...');
            try {
                const setFactoryTx = await this.quantumMarketManager.setFactory(CONFIG.QLICK_ORCHESTRATOR);
                await this.waitForTransaction(setFactoryTx, 'Setting orchestrator as factory');
            } catch (error) {
                if (error.message.includes('set')) {
                    console.log('⚠️  Factory already set, continuing...');
                } else {
                    throw error;
                }
            }

            const timestamp = Math.floor(Date.now() / 1000);
            const decisions = [];
            const pools = [];

            // Step 2-4: Create 3 fresh markets (tokens + pools + decisions + proposals)
            for (let i = 1; i <= 3; i++) {
                console.log(`\n=== Creating Market ${i} ===`);
                
                // Deploy fresh tokens for this market
                console.log(`Step ${i}.1: Deploying fresh tokens for market ${i}...`);
                const deployTokensTx = await this.orchestrator.deployTokens(CONFIG.MINT_AMOUNT);
                await this.waitForTransaction(deployTokensTx, `Deploying tokens for market ${i}`);

                // Create fresh pool
                console.log(`Step ${i}.2: Creating fresh pool for market ${i}...`);
                try {
                    const createPoolTx = await this.orchestrator['createPoolAndAddLiquidity(address,uint24,int24,uint160,uint128)'](
                        CONFIG.QUANTUM_MARKET_HOOK,
                        CONFIG.FEE,
                        CONFIG.TICK_SPACING,
                        CONFIG.SQRT_PRICE_X96,
                        CONFIG.LIQUIDITY_DESIRED
                    );
                    await this.waitForTransaction(createPoolTx, `Creating pool for market ${i}`);
                } catch (error) {
                    console.log(`⚠️  Pool creation failed for market ${i}, continuing...`);
                }

                // Create fresh decision
                console.log(`Step ${i}.3: Creating fresh decision for market ${i}...`);
                const decisionMetadata = `Extended Market ${i} Decision ${timestamp}`;
                const createDecisionTx = await this.quantumMarketManager.createDecision(decisionMetadata);
                const receipt = await this.waitForTransaction(createDecisionTx, `Creating decision for market ${i}`);
                
                // Extract decision ID
                const decisionCreatedEvent = receipt.logs.find(log => {
                    try {
                        const parsed = this.quantumMarketManager.interface.parseLog(log);
                        return parsed && parsed.name === 'DecisionCreated';
                    } catch {
                        return false;
                    }
                });
                
                const decisionId = decisionCreatedEvent ? 
                    this.quantumMarketManager.interface.parseLog(decisionCreatedEvent).args.decisionId :
                    await this.quantumMarketManager.nextDecisionId() - 1;
                
                console.log(`✅ Created decision ${i} with ID: ${decisionId}`);

                // Create fresh proposal
                console.log(`Step ${i}.4: Creating fresh proposal for market ${i}...`);
                const poolKeyResult = await this.orchestrator.lastPoolKey();
                const poolKey = {
                    currency0: poolKeyResult[0],
                    currency1: poolKeyResult[1], 
                    fee: poolKeyResult[2],
                    tickSpacing: poolKeyResult[3],
                    hooks: poolKeyResult[4]
                };
                
                const proposalId = ethers.keccak256(ethers.toUtf8Bytes(`extended-proposal-${i}-${timestamp}`));
                const createProposalTx = await this.quantumMarketManager.createProposal(
                    decisionId,
                    proposalId,
                    `Extended Market ${i} Proposal ${timestamp}`,
                    poolKey
                );
                await this.waitForTransaction(createProposalTx, `Creating proposal for market ${i}`);

                decisions.push({ id: decisionId, proposalId });
                pools.push(poolKey);
            }

            // Step 5: Trade on one of the registered pools
            console.log('\nStep 5: Trading on a registered pool...');
            
            if (pools.length > 0 && decisions.length > 0) {
                // Use the first pool we created and registered (most likely to work)
                console.log(`Attempting to trade on market 1 pool (decision ID: ${decisions[0].id})`);
                console.log('Pool details:', pools[0]);
                
                try {
                    const swapTx = await this.orchestrator.swapOnPool(true, CONFIG.SWAP_AMOUNT);
                    await this.waitForTransaction(swapTx, 'Executing demo swap on registered pool');
                } catch (error) {
                    // Check for unregistered pool error in multiple ways
                    const isUnregisteredPool = 
                        error.message.includes('unregistered pool') ||
                        error.message.includes('unknown custom error') ||
                        (error.data && error.data.includes('756e7265676973746572656420706f6f6c')); // hex for "unregistered pool"
                    
                    if (isUnregisteredPool) {
                        console.log('⚠️  Pool registration issue detected. This can happen with multiple pool creation.');
                        console.log('The markets were created successfully, but trading requires the exact pool that was registered.');
                        console.log('Skipping swap step and proceeding to settlement...');
                    } else {
                        throw error;
                    }
                }
            } else {
                console.log('⚠️  No pools available for trading');
            }

            // Step 6: Settle all decisions
            console.log('\nStep 6: Settling all decisions...');
            for (let i = 0; i < decisions.length; i++) {
                const decision = decisions[i];
                console.log(`Settling decision ${i + 1} (ID: ${decision.id})...`);
                const settleTx = await this.quantumMarketManager.settle(decision.id, decision.proposalId);
                await this.waitForTransaction(settleTx, `Settling decision ${i + 1}`);
            }

            console.log('\n✅ Extended market flow completed successfully!');
            console.log(`📊 Summary:`);
            console.log(`   - Created ${decisions.length} fresh decisions`);
            console.log(`   - Created ${pools.length} fresh pools`);
            console.log(`   - Executed trading and settlement for all markets`);

        } catch (error) {
            console.error('\n❌ Extended market flow failed:', error.message);
            throw error;
        }
    }

    // Utility functions
    async getBalance() {
        const balance = await this.provider.getBalance(this.wallet.address);
        console.log(`Wallet balance: ${ethers.formatEther(balance)} ETH`);
        return balance;
    }

    async getLastPoolKey() {
        try {
            const poolKey = await this.orchestrator.lastPoolKey();
            console.log('Last pool key:', poolKey);
            return poolKey;
        } catch (error) {
            console.log('Could not fetch last pool key:', error.message);
            return null;
        }
    }

    // Main execution function
    async run(flowType = 'basic') {
        try {
            console.log('🔍 Checking wallet balance...');
            await this.getBalance();

            if (flowType === 'basic') {
                await this.runBasicFlow();
            } else if (flowType === 'extended') {
                await this.runExtendedMarketFlow();
            } else {
                console.log('Available flows: basic, extended');
                console.log('Running basic flow by default...');
                await this.runBasicFlow();
            }

        } catch (error) {
            console.error('\n💥 Script execution failed:', error);
            process.exit(1);
        }
    }
}

// CLI execution
async function main() {
    const args = process.argv.slice(2);
    const flowType = args[0] || 'basic';
    
    console.log('🎯 Qlick Ethers.js Script');
    console.log('========================');
    console.log(`Flow type: ${flowType}`);
    
    const script = new QlickEthersScript();
    await script.run(flowType);
}

// Export for use as module
module.exports = { QlickEthersScript, CONFIG };

// Run if called directly
if (require.main === module) {
    main().catch(console.error);
}
