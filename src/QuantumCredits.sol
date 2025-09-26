// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title QuantumCredits
/// @notice Minimal non-transferable credit token used to represent shared trading credit across proposals
contract QuantumCredits {
    string public name = "Quantum Credits";
    string public symbol = "QCR";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public balanceOf;

    event Mint(address indexed to, uint256 amount);
    event Burn(address indexed from, uint256 amount);

    address public immutable controller;

    constructor(address _controller) {
        controller = _controller;
    }

    modifier onlyController() {
        require(msg.sender == controller, "not controller");
        _;
    }

    function mint(address to, uint256 amount) external onlyController {
        balanceOf[to] += amount;
        emit Mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyController {
        uint256 bal = balanceOf[from];
        require(bal >= amount, "insufficient");
        unchecked {
            balanceOf[from] = bal - amount;
        }
        emit Burn(from, amount);
    }
}


