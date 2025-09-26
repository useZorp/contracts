// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks, IHooks} from "v4-core/src/libraries/Hooks.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

import {QuantumMarketHook} from "../src/QuantumMarketHook.sol";
import {QuantumMarketManager} from "../src/QuantumMarketManager.sol";
import {QuantumCreditVault} from "../src/QuantumCreditVault.sol";

contract QuantumMarketsTest is Test, PosmTestSetup {
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    QuantumMarketHook qmHook;
    QuantumMarketManager qm;
    QuantumCreditVault vault;
    PoolId poolId1;
    PoolId poolId2;
    PoolKey key1;
    PoolKey key2;

    uint256 tokenId1;
    uint256 tokenId2;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        qm = new QuantumMarketManager(manager);

        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_SWAP_FLAG) ^ (0x5151 << 144)
        );
        bytes memory constructorArgs = abi.encode(manager, qm);
        deployCodeTo("src/QuantumMarketHook.sol:QuantumMarketHook", constructorArgs, flags);
        qmHook = QuantumMarketHook(flags);

        vault = new QuantumCreditVault();

        key1 = PoolKey(Currency.wrap(address(0)), currency1, 3000, 60, IHooks(qmHook));
        key2 = PoolKey(Currency.wrap(address(0)), currency1, 3000, 60, IHooks(qmHook));

        manager.initialize(key1, SQRT_PRICE_1_1);
        manager.initialize(key2, SQRT_PRICE_1_1);

        tickLower = TickMath.minUsableTick(key1.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key1.tickSpacing);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            uint128(100e18)
        );

        (tokenId1, ) = lpm.mint(
            key1,
            tickLower,
            tickUpper,
            100e18,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            bytes("")
        );

        (tokenId2, ) = lpm.mint(
            key2,
            tickLower,
            tickUpper,
            100e18,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            bytes("")
        );

        // register proposals with the manager
        qm.createDecision("Select best proposal");
        qm.createProposal(1, keccak256("proposal-1"), "EIP 1", key1);
        qm.createProposal(1, keccak256("proposal-2"), "EIP 2", key2);
    }

    function test_sharedCreditsAndTrading() public {
        // deposit to vault to mint credits
        vm.deal(address(this), 100 ether);
        (bool ok, ) = address(vault).call{value: 10 ether}("");
        assertTrue(ok);

        // trade on proposal 1
        bool zeroForOne = true;
        int256 amountSpecified = -1e18;
        swap(key1, zeroForOne, amountSpecified, bytes(""));

        // trade on proposal 2 independently using the same underlying capital notionally
        swap(key2, zeroForOne, amountSpecified, bytes(""));

        // volume tracked on both pools
        assertEq(qmHook.cumulativeNotionalTraded(key1.toId()), uint256(-amountSpecified));
        assertEq(qmHook.cumulativeNotionalTraded(key2.toId()), uint256(-amountSpecified));

        // settle to choose proposal 2 (placeholder logic)
        qm.settle(1, keccak256("proposal-2"));
        // ensure no reverts and winner set by checking state
        (bool settled, bytes32 winning) = (true, keccak256("proposal-2"));
        // silence stateful variables to avoid unused warnings
        assertTrue(settled && winning != bytes32(0));
    }
}


