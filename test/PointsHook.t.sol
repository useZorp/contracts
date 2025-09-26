// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {PosmTestSetup} from "v4-periphery/test/shared/PosmTestSetup.sol";
import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {Hooks, IHooks} from "v4-core/src/libraries/Hooks.sol";
import {PointsHook} from "../src/PointsHook.sol";
import {PointsToken} from "../src/PointsToken.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

contract PointsHookTest is Test, PosmTestSetup {
    using EasyPosm for IPositionManager;
    using StateLibrary for IPoolManager;

    PointsHook pointsHook;
    PointsToken pointsToken;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_ADD_LIQUIDITY_FLAG) ^
                (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("src/PointsHook.sol:PointsHook", constructorArgs, flags);
        pointsHook = PointsHook(flags);
        pointsToken = pointsHook.pointsToken();

        // Create the pool
        key = PoolKey(
            Currency.wrap(address(0)),
            currency1,
            3000,
            60,
            IHooks(pointsHook)
        );
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        deal(address(this), 200 ether);

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                uint128(100e18)
            );

        (tokenId, ) = lpm.mint(
            key,
            tickLower,
            tickUpper,
            100e18,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            pointsHook.getHookData(address(this))
        );
    }

    function test_PointsHook_Swap() public {
        // We already have some points because we added some liquidity during setup.
        // So, we'll subtract those from the total points to get the points awarded for this swap.
        uint256 startingPoints = pointsToken.balanceOf(address(this));

        // Let's swap some ETH for the token.
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(
            key,
            zeroForOne,
            amountSpecified,
            pointsHook.getHookData(address(this))
        );

        uint256 endingPoints = pointsToken.balanceOf(address(this));

        // Let's make sure we got the right amount of points!
        assertEq(
            endingPoints - startingPoints,
            uint256(-amountSpecified),
            "Points awarded for swap should be 1:1 with ETH"
        );
    }

    function test_PointsHook_Liquidity() public {
        // We already have some points because we added some liquidity during setup.
        // So, we'll subtract those from the total points to get the points awarded for this swap.
        uint256 startingPoints = pointsToken.balanceOf(address(this));

        uint128 liqToAdd = 100e18;

        (uint256 amount0, uint256 amount1) = LiquidityAmounts
            .getAmountsForLiquidity(
                SQRT_PRICE_1_1,
                TickMath.getSqrtPriceAtTick(tickLower),
                TickMath.getSqrtPriceAtTick(tickUpper),
                liqToAdd
            );

        lpm.mint(
            key,
            tickLower,
            tickUpper,
            liqToAdd,
            amount0 + 1,
            amount1 + 1,
            address(this),
            block.timestamp,
            pointsHook.getHookData(address(this))
        );

        uint256 endingPoints = pointsToken.balanceOf(address(this));

        // Let's make sure we got the right amount of points!
        assertApproxEqAbs(endingPoints - startingPoints, uint256(liqToAdd), 10);
    }
}