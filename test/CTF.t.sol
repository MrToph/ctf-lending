// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/Test.sol";

import {ERC20} from "src/ERC20.sol";
import {Attacker} from "src/Attacker.sol";
import {LendingProtocol} from "src/LendingProtocol.sol";
import {IUniswapV2Factory, IUniswapV2Pair} from "src/IUniswapV2.sol";

contract CTFTest is Test {
    Attacker internal attacker;
    ERC20 internal ctf; // token0
    ERC20 internal usd; // token1
    IUniswapV2Pair internal pair;
    LendingProtocol internal lending;

    function setUp() public {
        // 0. create tokens
        usd = new ERC20("USD Token", "USD", 18);
        ctf = new ERC20("CTF Token", "CTF", 18);

        // 1. create Uniswap pair for tokens
        IUniswapV2Factory uniswapFactory = IUniswapV2Factory(deployCode("out/UniswapV2Factory.sol/UniswapV2Factory.json", abi.encode(address(0))));
          pair = IUniswapV2Pair(
            uniswapFactory.createPair(address(ctf), address(usd))
        );

        // 2. create lending protocol
        lending = new LendingProtocol(address(ctf), address(usd), pair);

        // 3. add initial liquidity at a CTF price (denoted in USD) of 1_000
        usd.mint(address(pair), 1_000 * 1e18);
        ctf.mint(address(pair), 1 * 1e18);
        pair.mint(address(this));

        // 4. victim (0xEEEE...) deposits 50k USD
        uint256 victimAmount = 50_000 * 1e18;
        usd.mint(address(this), victimAmount);
        usd.approve(address(lending), victimAmount);
        lending.deposit(
            address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
            address(usd),
            victimAmount
        );

        // 5. create attacker with 10k of USD and CTF tokens each
        attacker = new Attacker(ctf, usd, pair, lending);
        usd.mint(address(attacker), 10_000 * 1e18);
        ctf.mint(address(attacker), 10 * 1e18);
    }

    function testSolved() public {
        // run the attacker contract
        attacker.attack();

        // contract with victim's USD deposit should be empty after attack
        assertEq(usd.balanceOf(address(lending)), 0);
    }
}
