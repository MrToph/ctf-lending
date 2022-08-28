// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import {ERC20 as ERC20Base} from "solmate/tokens/ERC20.sol";

contract ERC20 is ERC20Base {
    error Unauthorized();

    address public immutable owner;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) payable ERC20Base(_name, _symbol, _decimals) {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external payable {
        if (msg.sender != owner) revert Unauthorized();
        _mint(to, amount);
    }
}
