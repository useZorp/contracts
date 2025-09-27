// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {QuantumMarketManager} from "../src/QuantumMarketManager.sol";

contract RegisterDecisionAndProposals is Script {
    function run(address qmAddress, address currency0, address currency1, address hooks, uint24 fee, int24 tickSpacing)
        external
    {
        QuantumMarketManager qm = QuantumMarketManager(qmAddress);

        vm.startBroadcast();
        uint256 decisionId = qm.createDecision("Qlick Demo: Choose best proposal");

        PoolKey memory key1 = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            fee,
            tickSpacing,
            IHooks(hooks)
        );
        PoolKey memory key2 = PoolKey(
            Currency.wrap(currency0),
            Currency.wrap(currency1),
            fee,
            tickSpacing,
            IHooks(hooks)
        );

        bytes32 p1 = keccak256("proposal-1");
        bytes32 p2 = keccak256("proposal-2");
        qm.createProposal(decisionId, p1, "EIP 1", key1);
        qm.createProposal(decisionId, p2, "EIP 2", key2);
        vm.stopBroadcast();

        console.log("Registered decision:", decisionId);
        console.log("Proposals:", bytes32(p1), bytes32(p2));
    }
}


