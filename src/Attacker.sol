// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2.sol";
import {LendingProtocol} from "./LendingProtocol.sol";


/// @title Attacker
/// @author Christoph Michel <cmichel.io>
contract Attacker {
    IUniswapV2Pair public immutable pair; // token0 <> token1 uniswapv2 pair
    ERC20 public immutable ctf; // token0
    ERC20 public immutable usd; // token1
    LendingProtocol public immutable lending;

    constructor(
        ERC20 _ctf,
        ERC20 _usd,
        IUniswapV2Pair _pair,
        LendingProtocol _lending
    ) {
        ctf = _ctf;
        usd = _usd;
        pair = _pair;
        lending = _lending;
    }

    function attack() external {
        console.log("implement attack here");
    }
}
