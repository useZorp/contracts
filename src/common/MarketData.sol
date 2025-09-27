// SPDX-License-Identifier: All Rights Reserved
pragma solidity >=0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";

enum MarketStatus { OPEN, PROPOSAL_ACCEPTED, TIMEOUT, RESOLVED_YES, RESOLVED_NO }

struct MarketConfig {
    uint256 id;
    uint256 createdAt;
    uint256 minDeposit;
    uint256 deadline;
    address creator;
    address marketToken;
    address resolver;
    MarketStatus status;
    string title;
}

struct ProposalTokens {
    address vUSD;
    address yesToken;
    address noToken;
}

struct ProposalConfig {
    uint256 id;
    uint256 marketId;
    uint256 createdAt;
    address creator;
    ProposalTokens tokens;
    PoolKey yesPoolKey;
    PoolKey noPoolKey;
    bytes data;
}


