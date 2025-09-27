// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {DecisionToken, TokenType, VUSD} from "./Tokens.sol";
import {MarketStatus, MarketConfig, ProposalConfig, ProposalTokens} from "./common/MarketData.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";

/// @title QuantumMarketManager
/// @notice Manages decisions and proposals for a simplified Quantum Markets demo using Uniswap v4 hooks
contract QuantumMarketManager {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    event DecisionCreated(uint256 indexed decisionId, string metadata);
    event ProposalCreated(uint256 indexed decisionId, bytes32 indexed proposalId, PoolKey poolKey);
    event Settled(uint256 indexed decisionId, bytes32 indexed winningProposalId);
    event MarketCreated(uint256 indexed marketId, uint256 createdAt, address creator, string title);

    struct Decision {
        string metadata; // human-readable description/question
        bool settled;
        bytes32 winningProposalId;
        bytes32[] proposals; // list for iteration in settle demo
    }

    struct ProposalInfo {
        uint256 decisionId;
        string metadata;
        PoolKey poolKey; // pool representing the proposal's market
        bool exists;
    }

    IPoolManager public immutable poolManager;
    IPositionManager public positionManager;
    IPermit2 public permit2;

    uint256 public nextDecisionId;
    mapping(uint256 => Decision) public decisions;
    mapping(bytes32 => ProposalInfo) public proposalInfo; // proposalId => info

    // lightweight market-style tracking for hook interactions
    mapping(PoolId => uint256) public poolToDecision; // which decision a pool belongs to
    mapping(PoolId => int24) public lastAvgTick; // latest avg tick observed via hook

    // market storage (single-market, multi-proposal minimal impl)
    mapping(uint256 => MarketConfig) public markets;
    mapping(uint256 => ProposalConfig) public proposals;
    mapping(PoolId => uint256) public poolToProposal;
    uint256 public acceptedProposal;

    // deposits and claims
    mapping(uint256 => mapping(address => uint256)) public deposits;
    mapping(uint256 => mapping(address => uint256)) public proposalDepositClaims;
    uint256 public nextProposalId;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function createDecision(string memory metadata) external returns (uint256 decisionId) {
        decisionId = ++nextDecisionId;
        decisions[decisionId].metadata = metadata;
        emit DecisionCreated(decisionId, metadata);
    }

    function createMarket(
        address creator,
        address marketToken,
        address resolver,
        uint256 minDeposit,
        uint256 deadline,
        string memory title
    ) external returns (uint256 marketId) {
        marketId = ++nextDecisionId;
        markets[marketId] = MarketConfig({
            id: marketId,
            createdAt: block.timestamp,
            minDeposit: minDeposit,
            deadline: deadline,
            creator: creator,
            marketToken: marketToken,
            resolver: resolver,
            status: MarketStatus.OPEN,
            title: title
        });
        emit MarketCreated(marketId, block.timestamp, creator, title);
    }

    function depositToMarket(address depositor, uint256 marketId, uint256 amount) external {
        MarketConfig memory m = markets[marketId];
        require(m.id != 0, "market");
        IERC20(m.marketToken).transferFrom(depositor, address(this), amount);
        deposits[marketId][depositor] += amount;
    }

    function createProposalForMarket(uint256 marketId, bytes memory data) external returns (uint256 proposalId) {
        MarketConfig memory m = markets[marketId];
        require(m.id != 0, "market");
        require(m.status == MarketStatus.OPEN, "closed");
        uint256 totalDeposited = deposits[marketId][msg.sender];
        uint256 alreadyClaimed = proposalDepositClaims[marketId][msg.sender];
        uint256 claimable = totalDeposited - alreadyClaimed;
        require(claimable >= m.minDeposit, "min deposit");
        proposalDepositClaims[marketId][msg.sender] = alreadyClaimed + m.minDeposit;

        // budgets
        uint256 D = m.minDeposit;
        uint256 burnTotal = (D * 2) / 3; // 2/3 to YES+NO
        uint256 tokenPerPool = burnTotal / 2;
        uint256 vusdToMint = D - burnTotal; // 1/3 to vUSD
        uint256 vusdPerPool = vusdToMint / 2;

        // deploy tokens; manager is minter
        VUSD vUSD = new VUSD(address(this));
        DecisionToken yesToken = new DecisionToken(TokenType.YES, address(this));
        DecisionToken noToken = new DecisionToken(TokenType.NO, address(this));

        // seed tokens: keep pool seed in manager, give user trading inventory
        yesToken.mint(address(this), tokenPerPool);
        noToken.mint(address(this), tokenPerPool);
        yesToken.mint(msg.sender, tokenPerPool);
        noToken.mint(msg.sender, tokenPerPool);
        // mint vUSD budget to the manager for seeding pools via seedProposalPools
        vUSD.mint(address(this), vusdToMint);

        proposalId = ++nextProposalId;
        proposals[proposalId] = ProposalConfig({
            id: proposalId,
            marketId: marketId,
            createdAt: block.timestamp,
            creator: msg.sender,
            tokens: ProposalTokens({ vUSD: address(vUSD), yesToken: address(yesToken), noToken: address(noToken) }),
            yesPoolKey: PoolKey({currency0: Currency.wrap(address(0)), currency1: Currency.wrap(address(0)), fee: 0, tickSpacing: 0, hooks: IHooks(address(0))}),
            noPoolKey: PoolKey({currency0: Currency.wrap(address(0)), currency1: Currency.wrap(address(0)), fee: 0, tickSpacing: 0, hooks: IHooks(address(0))}),
            data: data
        });
    }

    function setProposalPools(uint256 proposalId, PoolKey calldata yesKey, PoolKey calldata noKey) external {
        ProposalConfig storage p = proposals[proposalId];
        require(p.id != 0, "proposal");
        require(p.yesPoolKey.tickSpacing == 0 && p.noPoolKey.tickSpacing == 0, "set");
        p.yesPoolKey = yesKey;
        p.noPoolKey = noKey;
        poolToProposal[yesKey.toId()] = proposalId;
        poolToProposal[noKey.toId()] = proposalId;
        poolToDecision[yesKey.toId()] = p.marketId;
        poolToDecision[noKey.toId()] = p.marketId;
    }

    function setPeriphery(IPositionManager _pos, IPermit2 _permit2) external {
        require(address(positionManager) == address(0) && address(permit2) == address(0), "set");
        positionManager = _pos;
        permit2 = _permit2;
    }

    function seedProposalPools(
        uint256 proposalId,
        address hook,
        uint24 fee,
        int24 spacing,
        uint160 sqrtPriceX96,
        uint128 liquidityDesired
    ) external {
        ProposalConfig storage p = proposals[proposalId];
        require(p.id != 0, "proposal");
        require(address(positionManager) != address(0), "periphery");

        IERC20(p.tokens.vUSD).approve(address(permit2), type(uint256).max);
        IERC20(p.tokens.yesToken).approve(address(permit2), type(uint256).max);
        IERC20(p.tokens.noToken).approve(address(permit2), type(uint256).max);
        permit2.approve(p.tokens.vUSD, address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(p.tokens.yesToken, address(positionManager), type(uint160).max, type(uint48).max);
        permit2.approve(p.tokens.noToken, address(positionManager), type(uint160).max, type(uint48).max);

        (address y0, address y1) = p.tokens.yesToken < p.tokens.vUSD
            ? (p.tokens.yesToken, p.tokens.vUSD)
            : (p.tokens.vUSD, p.tokens.yesToken);
        PoolKey memory yesKey = PoolKey({
            currency0: Currency.wrap(y0),
            currency1: Currency.wrap(y1),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hook)
        });
        poolManager.initialize(yesKey, sqrtPriceX96);

        (address n0, address n1) = p.tokens.noToken < p.tokens.vUSD
            ? (p.tokens.noToken, p.tokens.vUSD)
            : (p.tokens.vUSD, p.tokens.noToken);
        PoolKey memory noKey = PoolKey({
            currency0: Currency.wrap(n0),
            currency1: Currency.wrap(n1),
            fee: fee,
            tickSpacing: spacing,
            hooks: IHooks(hook)
        });
        poolManager.initialize(noKey, sqrtPriceX96);

        int24 lower = TickMath.minUsableTick(spacing);
        int24 upper = TickMath.maxUsableTick(spacing);
        (uint256 a0, uint256 b0) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(lower),
            TickMath.getSqrtPriceAtTick(upper),
            liquidityDesired
        );
        bytes memory actions = abi.encodePacked(uint8(0x11), uint8(0x12));
        {
            bytes[] memory ps = new bytes[](2);
            ps[0] = abi.encode(yesKey, lower, upper, liquidityDesired, a0 + 1, b0 + 1, address(this), bytes(""));
            ps[1] = abi.encode(yesKey.currency0, yesKey.currency1);
            positionManager.modifyLiquidities(abi.encode(actions, ps), block.timestamp + 60);
        }
        {
            bytes[] memory ps = new bytes[](2);
            ps[0] = abi.encode(noKey, lower, upper, liquidityDesired, a0 + 1, b0 + 1, address(this), bytes(""));
            ps[1] = abi.encode(noKey.currency0, noKey.currency1);
            positionManager.modifyLiquidities(abi.encode(actions, ps), block.timestamp + 60);
        }

        p.yesPoolKey = yesKey;
        p.noPoolKey = noKey;
        poolToProposal[yesKey.toId()] = proposalId;
        poolToProposal[noKey.toId()] = proposalId;
        poolToDecision[yesKey.toId()] = p.marketId;
        poolToDecision[noKey.toId()] = p.marketId;
    }

    function acceptProposal(uint256 marketId, uint256 proposalId) external {
        MarketConfig storage m = markets[marketId];
        require(m.status == MarketStatus.OPEN || m.status == MarketStatus.PROPOSAL_ACCEPTED, "status");
        require(proposals[proposalId].marketId == marketId, "mismatch");
        m.status = MarketStatus.PROPOSAL_ACCEPTED;
        acceptedProposal = proposalId;
    }

    /// @notice Registers a proposal and its dedicated poolKey that uses a shared hook
    /// @dev The pool must be created/initialized elsewhere (periphery) and use a hook that references this manager
    function createProposal(
        uint256 decisionId,
        bytes32 proposalId,
        string memory metadata,
        PoolKey memory poolKey
    ) external {
        require(!decisions[decisionId].settled, "settled");
        require(!proposalInfo[proposalId].exists, "exists");
        // basic sanity: ensure hook is set on the pool key (we don't enforce specific address here)
        require(address(poolKey.hooks) != address(0), "no hook");

        decisions[decisionId].proposals.push(proposalId);
        proposalInfo[proposalId] = ProposalInfo({
            decisionId: decisionId,
            metadata: metadata,
            poolKey: poolKey,
            exists: true
        });

        emit ProposalCreated(decisionId, proposalId, poolKey);

        // register pool -> decision for hook validation
        poolToDecision[poolKey.toId()] = decisionId;
    }

    /// @notice Demo settle function: governance/keeper provides the winning proposal id
    /// In a production-like system, selection would be derived from on-chain observable metrics (e.g., TWAP, volumes)
    function settle(uint256 decisionId, bytes32 winningProposalId) external {
        Decision storage d = decisions[decisionId];
        require(!d.settled, "settled");
        require(proposalInfo[winningProposalId].exists, "bad proposal");
        require(proposalInfo[winningProposalId].decisionId == decisionId, "mismatch");

        d.settled = true;
        d.winningProposalId = winningProposalId;
        emit Settled(decisionId, winningProposalId);
    }

    // === Hook entry points ===
    function validateSwap(PoolKey calldata key) external view {
        uint256 did = poolToDecision[key.toId()];
        require(did != 0, "unregistered pool");
        require(!decisions[did].settled, "market closed");
    }

    function updatePostSwap(PoolKey calldata key, int24 avgTick) external {
        lastAvgTick[key.toId()] = avgTick;
    }

    function resolveMarket(uint256 marketId, bool yesOrNo) external {
        MarketConfig storage m = markets[marketId];
        require(m.status == MarketStatus.PROPOSAL_ACCEPTED, "not accepted");
        m.status = yesOrNo ? MarketStatus.RESOLVED_YES : MarketStatus.RESOLVED_NO;
    }

    function redeemRewards(uint256 marketId, address user) external {
        MarketConfig memory m = markets[marketId];
        require(m.status == MarketStatus.RESOLVED_YES || m.status == MarketStatus.RESOLVED_NO, "unresolved");
        uint256 winning = acceptedProposal;
        ProposalConfig memory p = proposals[winning];
        VUSD vUSD = VUSD(p.tokens.vUSD);
        DecisionToken yesToken = DecisionToken(p.tokens.yesToken);
        DecisionToken noToken = DecisionToken(p.tokens.noToken);

        uint256 rewards = vUSD.balanceOf(user);
        if (rewards > 0) vUSD.burnFrom(user, rewards);
        if (m.status == MarketStatus.RESOLVED_YES) {
            uint256 bal = yesToken.balanceOf(user);
            if (bal > 0) { yesToken.burnFrom(user, bal); rewards += bal; }
        } else {
            uint256 bal = noToken.balanceOf(user);
            if (bal > 0) { noToken.burnFrom(user, bal); rewards += bal; }
        }
        IERC20(m.marketToken).transfer(user, rewards);
    }
}


