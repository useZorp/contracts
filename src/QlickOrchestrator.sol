// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {QuantumMarketManager} from "./QuantumMarketManager.sol";
import {VUSD, DecisionToken, TokenType} from "./Tokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract QlickOrchestrator {
    using CurrencyLibrary for Currency;

    event TokensDeployed(address token0, address token1);
    event PoolCreated(PoolId poolId);
    event LiquidityAdded(uint256 tokenId, uint128 liquidity);
    event DecisionRegistered(uint256 decisionId, bytes32 proposal1, bytes32 proposal2);
    event MarketCreated(uint256 marketId);

    IPoolManager public immutable poolManager;
    IPositionManager public immutable positionManager;
    IPermit2 public immutable permit2;
    IUniswapV4Router04 public immutable swapRouter;

    MockERC20 public token0;
    MockERC20 public token1;

    PoolKey public lastPoolKey;
    uint256 public lastTokenId;
    uint256 public lastDecisionId;
    bytes32 public lastProposal1;
    bytes32 public lastProposal2;
    uint256 public lastMarketId;

    constructor(
        IPoolManager _poolManager,
        IPositionManager _positionManager,
        IPermit2 _permit2,
        IUniswapV4Router04 _swapRouter
    ) {
        poolManager = _poolManager;
        positionManager = _positionManager;
        permit2 = _permit2;
        swapRouter = _swapRouter;
    }

    function deployTokens(uint256 mintAmount) external {
        token0 = new MockERC20("QlickToken0", "QT0", 18);
        token1 = new MockERC20("QlickToken1", "QT1", 18);
        token0.mint(address(this), mintAmount);
        token1.mint(address(this), mintAmount);
        emit TokensDeployed(address(token0), address(token1));
    }

    function createPoolAndAddLiquidity(
        address hook,
        uint24 fee,
        int24 tickSpacing,
        uint160 sqrtPriceX96,
        uint128 liquidityDesired
    ) external {
        require(address(token0) != address(0) && address(token1) != address(0), "tokens not deployed");

        // Approvals for PositionManager via Permit2 pattern
        token0.approve(address(permit2), type(uint256).max);
        token1.approve(address(permit2), type(uint256).max);
        permit2.approve(address(token0), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(token1), address(positionManager), type(uint160).max, type(uint48).max);

        Currency c0 = Currency.wrap(address(token0));
        Currency c1 = Currency.wrap(address(token1));

        // Order currencies
        if (!(c0 < c1)) {
            (c0, c1) = (c1, c0);
        }

        PoolKey memory key = PoolKey({currency0: c0, currency1: c1, fee: fee, tickSpacing: tickSpacing, hooks: IHooks(hook)});

        // Initialize pool
        poolManager.initialize(key, sqrtPriceX96);

        // Compute amounts for liquidity
        int24 tickLower = TickMath.minUsableTick(tickSpacing);
        int24 tickUpper = TickMath.maxUsableTick(tickSpacing);
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityDesired
        );

        // Build modifyLiquidities call
        bytes memory actions = abi.encodePacked(uint8(0x11) /* MINT_POSITION */, uint8(0x12) /* SETTLE_PAIR */);
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, liquidityDesired, amount0 + 1, amount1 + 1, address(this), bytes(""));
        params[1] = abi.encode(key.currency0, key.currency1);

        uint256 nextIdBefore = positionManager.nextTokenId();
        positionManager.modifyLiquidities(abi.encode(actions, params), block.timestamp + 3600);
        uint256 tokenId = nextIdBefore; // minted id

        lastPoolKey = key;
        lastTokenId = tokenId;
        emit PoolCreated(key.toId());
        emit LiquidityAdded(tokenId, liquidityDesired);
    }

    function registerDecision(QuantumMarketManager qm) external {
        require(lastPoolKey.tickSpacing != 0, "pool not created");
        uint256 decisionId = qm.createDecision("Qlick: Best proposal");
        bytes32 p1 = keccak256("proposal-1");
        bytes32 p2 = keccak256("proposal-2");
        qm.createProposal(decisionId, p1, "EIP 1", lastPoolKey);
        qm.createProposal(decisionId, p2, "EIP 2", lastPoolKey);
        lastDecisionId = decisionId;
        lastProposal1 = p1;
        lastProposal2 = p2;
        emit DecisionRegistered(decisionId, p1, p2);
    }

    // New: full market flow
    function createMarket(QuantumMarketManager qm, address marketToken, address resolver, uint256 minDeposit, uint256 deadline, string calldata title) external {
        lastMarketId = qm.createMarket(msg.sender, marketToken, resolver, minDeposit, deadline, title);
        emit MarketCreated(lastMarketId);
    }

    function createProposalWithDualPools(
        QuantumMarketManager qm,
        address hook,
        uint24 fee,
        int24 spacing,
        uint160 sqrtPriceX96,
        uint128 liquidityDesired
    ) external returns (uint256 proposalId, PoolKey memory yesKey, PoolKey memory noKey) {
        require(lastMarketId != 0, "market not created");
        // step 1: ensure ERC20 budgets exist
        // depositToMarket should be called off-chain to move user's marketToken to manager
        // step 2: create proposal and mint tokens
        proposalId = qm.createProposalForMarket(lastMarketId, bytes(""));

        // step 3: initialize two pools YES/VUSD and NO/VUSD
        // For demo, we create mock tokens here and use them; in prod, caller would supply tokens
        VUSD vUSD = new VUSD(address(this));
        DecisionToken yesToken = new DecisionToken(TokenType.YES, address(this));
        DecisionToken noToken = new DecisionToken(TokenType.NO, address(this));
        vUSD.mint(address(this), 1e24);
        yesToken.mint(address(this), 1e24);
        noToken.mint(address(this), 1e24);

        // Approvals
        IERC20(address(vUSD)).approve(address(permit2), type(uint256).max);
        IERC20(address(yesToken)).approve(address(permit2), type(uint256).max);
        IERC20(address(noToken)).approve(address(permit2), type(uint256).max);
        permit2.approve(address(vUSD), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(yesToken), address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(address(noToken), address(positionManager), type(uint160).max, type(uint48).max);

        (address t0a, address t1a) = address(yesToken) < address(vUSD) ? (address(yesToken), address(vUSD)) : (address(vUSD), address(yesToken));
        (address t0b, address t1b) = address(noToken) < address(vUSD) ? (address(noToken), address(vUSD)) : (address(vUSD), address(noToken));
        yesKey = PoolKey({ currency0: Currency.wrap(t0a), currency1: Currency.wrap(t1a), fee: fee, tickSpacing: spacing, hooks: IHooks(hook) });
        noKey  = PoolKey({ currency0: Currency.wrap(t0b), currency1: Currency.wrap(t1b), fee: fee, tickSpacing: spacing, hooks: IHooks(hook) });

        poolManager.initialize(yesKey, sqrtPriceX96);
        poolManager.initialize(noKey, sqrtPriceX96);

        int24 lower = TickMath.minUsableTick(spacing);
        int24 upper = TickMath.maxUsableTick(spacing);
        (uint256 a0, uint256 b0) = LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, TickMath.getSqrtPriceAtTick(lower), TickMath.getSqrtPriceAtTick(upper), liquidityDesired);
        (uint256 a1, uint256 b1) = (a0, b0);

        bytes memory actions = abi.encodePacked(uint8(0x11), uint8(0x12));
        {
            bytes[] memory ps = new bytes[](2);
            ps[0] = abi.encode(yesKey, lower, upper, liquidityDesired, a0 + 1, b0 + 1, address(this), bytes(""));
            ps[1] = abi.encode(yesKey.currency0, yesKey.currency1);
            positionManager.modifyLiquidities(abi.encode(actions, ps), block.timestamp + 3600);
        }
        {
            bytes[] memory ps = new bytes[](2);
            ps[0] = abi.encode(noKey, lower, upper, liquidityDesired, a1 + 1, b1 + 1, address(this), bytes(""));
            ps[1] = abi.encode(noKey.currency0, noKey.currency1);
            positionManager.modifyLiquidities(abi.encode(actions, ps), block.timestamp + 3600);
        }

        // link pools to proposal in manager
        qm.setProposalPools(proposalId, yesKey, noKey);
    }

    function swapOnPool(bool zeroForOne, uint256 amountIn) external {
        require(lastPoolKey.tickSpacing != 0, "pool not created");
        // Approve router
        MockERC20(Currency.unwrap(zeroForOne ? lastPoolKey.currency0 : lastPoolKey.currency1)).approve(
            address(swapRouter), type(uint256).max
        );
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: zeroForOne,
            poolKey: lastPoolKey,
            hookData: bytes(""),
            receiver: address(this),
            deadline: block.timestamp + 30
        });
    }
}


