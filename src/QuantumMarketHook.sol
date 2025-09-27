// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@uniswap/v4-periphery/src/utils/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMarket} from "./interfaces/IMarket.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

contract QuantumMarketHook is BaseHook, Ownable {
    using PoolIdLibrary for PoolKey;

    address public market;
    bool private initialized;

    struct Obs { uint32 time; int56 tickCumulative; int24 lastTick; }
    mapping(PoolId => Obs) public lastObs;

    constructor(IPoolManager pm) BaseHook(pm) Ownable(msg.sender) {}

    function initialize(address _market) external {
        require(!initialized, "initialized");
        initialized = true;
        market = _market;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        IMarket(market).validateSwap(key);
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        PoolId id = key.toId();
        Obs storage o = lastObs[id];
        (, int24 tick,,) = StateLibrary.getSlot0(poolManager, id);
        uint32 now32 = uint32(block.timestamp);

        if (o.time != 0) {
            o.tickCumulative += int56(o.lastTick) * int56(uint56(now32 - o.time));
        }

        if (o.time != 0 && now32 - o.time >= 30) {
            // 30s window using the observation stored below (simple approx)
            int56 tickNowCum = o.tickCumulative + int56(tick) * int56(uint56(now32 - o.time));
            int56 tickAgoCum = tickNowCum - int56(tick) * int56(uint56(30));
            int24 avg = int24((tickNowCum - tickAgoCum) / int56(uint56(30)));
            try IMarket(market).updatePostSwap(key, avg) {} catch {}
        }

        o.time = now32;
        o.lastTick = tick;
        return (BaseHook.afterSwap.selector, 0);
    }
}


