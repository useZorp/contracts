// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

import {QlickOrchestrator} from "../src/QlickOrchestrator.sol";

contract QlickOrchestratorDeploy is Script {
    function run() external {
        vm.startBroadcast();
        QlickOrchestrator orch = new QlickOrchestrator(
            IPoolManager(0x00B036B58a818B1BC34d502D3fE730Db729e62AC),
            IPositionManager(payable(0xf969Aee60879C54bAAed9F3eD26147Db216Fd664)),
            IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3),
            IUniswapV4Router04(payable(0x9cD2b0a732dd5e023a5539921e0FD1c30E198Dba))
        );
        vm.stopBroadcast();
    }
}
