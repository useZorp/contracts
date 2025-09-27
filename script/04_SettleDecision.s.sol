// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {QuantumMarketManager} from "../src/QuantumMarketManager.sol";

contract SettleDecision is Script {
    function run(address qmAddress, uint256 decisionId, bytes32 winningProposalId) external {
        vm.startBroadcast();
        QuantumMarketManager(qmAddress).settle(decisionId, winningProposalId);
        vm.stopBroadcast();
        console.log("Settled decision", decisionId, "with", winningProposalId);
    }
}


