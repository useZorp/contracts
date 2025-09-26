// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {QuantumCredits} from "./QuantumCredits.sol";

/// @title QuantumCreditVault
/// @notice Accepts deposits and issues credits that are recognized across all proposals in a decision
/// @dev Demo only; no ERC4626, no asset accounting. Credits simply mirror deposits for simplicity.
contract QuantumCreditVault {
    QuantumCredits public immutable credits;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor() {
        credits = new QuantumCredits(address(this));
    }

    receive() external payable {
        deposit();
    }

    function deposit() public payable {
        require(msg.value > 0, "zero");
        credits.mint(msg.sender, msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        credits.burn(msg.sender, amount);
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "eth send failed");
        emit Withdrawn(msg.sender, amount);
    }
}


