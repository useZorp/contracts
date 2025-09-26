// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IHooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";

/// @title QuantumMarketManager
/// @notice Manages decisions and proposals for a simplified Quantum Markets demo using Uniswap v4 hooks
contract QuantumMarketManager {
    using PoolIdLibrary for PoolKey;

    event DecisionCreated(uint256 indexed decisionId, string metadata);
    event ProposalCreated(uint256 indexed decisionId, bytes32 indexed proposalId, PoolKey poolKey);
    event Settled(uint256 indexed decisionId, bytes32 indexed winningProposalId);

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

    uint256 public nextDecisionId;
    mapping(uint256 => Decision) public decisions;
    mapping(bytes32 => ProposalInfo) public proposalInfo; // proposalId => info

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    function createDecision(string memory metadata) external returns (uint256 decisionId) {
        decisionId = ++nextDecisionId;
        decisions[decisionId].metadata = metadata;
        emit DecisionCreated(decisionId, metadata);
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
}


