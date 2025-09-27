// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console2 as console} from "forge-std/console2.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {AddressConstants} from "hookmate/constants/AddressConstants.sol";

import {QuantumMarketHook} from "../src/QuantumMarketHook.sol";
import {QuantumMarketManager} from "../src/QuantumMarketManager.sol";

contract DeployQlickScript is Script {
	// CREATE2 deployer used by Foundry scripts on public networks
	address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

	function run() external {
		uint256 chainId = block.chainid;
		IPoolManager poolManager = IPoolManager(AddressConstants.getPoolManagerAddress(chainId));

		vm.startBroadcast();
		QuantumMarketManager qm = new QuantumMarketManager(poolManager);
		vm.stopBroadcast();

		// Hook must encode EXACTLY the flags it implements: BEFORE_SWAP | AFTER_SWAP
		uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);

		bytes memory constructorArgs = abi.encode(poolManager);
		(address hookAddress, bytes32 salt) =
			HookMiner.find(CREATE2_DEPLOYER, flags, type(QuantumMarketHook).creationCode, constructorArgs);

		vm.startBroadcast();
		QuantumMarketHook hook = new QuantumMarketHook{salt: salt}(poolManager);
		hook.initialize(address(qm));
		vm.stopBroadcast();

		require(address(hook) == hookAddress, "DeployQlick: hook address mismatch");

		console.log("Qlick deployed");
		console.log("PoolManager:", address(poolManager));
		console.log("QuantumMarketManager:", address(qm));
		console.log("QuantumMarketHook:", address(hook));
	}
}


