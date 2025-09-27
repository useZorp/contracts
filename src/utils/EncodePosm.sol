// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Helper to ABI-encode PositionManager.modifyLiquidities payloads
contract EncodePosm {
    function encodeModifyRaw(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing,
        address hook,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        uint256 amount0Max,
        uint256 amount1Max,
        address recipient,
        bytes calldata hookData
    ) external pure returns (bytes memory data) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hook)
        });

        bytes memory actions = abi.encodePacked(uint8(0x11), uint8(0x12));
        bytes[] memory params = new bytes[](2);
        params[0] = abi.encode(key, tickLower, tickUpper, liquidity, amount0Max, amount1Max, recipient, hookData);
        params[1] = abi.encode(Currency.unwrap(key.currency0), Currency.unwrap(key.currency1));
        data = abi.encode(actions, params);
    }
}


