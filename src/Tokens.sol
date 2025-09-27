// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

enum TokenType { YES, NO }

abstract contract ERC20Mintable is ERC20, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    error CallerNotMinter(address caller);

    constructor(address minter, string memory n, string memory s) ERC20(n, s) {
        _grantRole(MINTER_ROLE, minter);
    }

    function mint(address to, uint256 amount) public {
        if (!hasRole(MINTER_ROLE, msg.sender)) revert CallerNotMinter(msg.sender);
        _mint(to, amount);
    }
}

contract DecisionToken is ERC20Burnable, ERC20Mintable {
    TokenType public tokenType;
    constructor(TokenType _type, address minter)
        ERC20Mintable(minter, _type == TokenType.YES ? "YES" : "NO", _type == TokenType.YES ? "YES" : "NO")
    {
        tokenType = _type;
    }
}

contract VUSD is ERC20Burnable, ERC20Mintable {
    constructor(address minter) ERC20Mintable(minter, "Virtual USDC", "VUSD") {}
}


