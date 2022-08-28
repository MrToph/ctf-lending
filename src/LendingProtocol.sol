// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.15;

import "forge-std/console.sol";
import {ERC20} from "./ERC20.sol";
import {IUniswapV2Pair} from "./IUniswapV2.sol";
import {SqrtMath} from "./SqrtMath.sol";

/// @title CTF
/// @author Christoph Michel <cmichel.io>
contract LendingProtocol {
    error InvalidArguments();
    error TransferFailed();
    error UnderCollateralized(uint256 collateralValue, uint256 debtValue);

    struct Position {
        mapping(address => uint256) amounts; // token => amount
    }

    address public immutable ctf; // token0
    address public immutable usd; // token1
    address public immutable pair; // token0 <> token1 uniswapv2 pair
    mapping(address => Position) userCollateral;
    mapping(address => Position) userDebt;

    constructor(
        address _ctf,
        address _usd,
        IUniswapV2Pair _pair
    ) {
        ctf = _ctf;
        usd = _usd;
        pair = address(_pair);
        if (
            !((_pair.token0() == _ctf && _pair.token1() == _usd) ||
                (_pair.token0() == _ctf && _pair.token1() == _usd))
        ) {
            revert InvalidArguments();
        }
    }

    function deposit(
        address to,
        address token,
        uint256 amount
    ) external payable {
        userCollateral[to].amounts[token] += amount;
        if (!ERC20(token).transferFrom(msg.sender, address(this), amount))
            revert TransferFailed();
    }

    function withdraw(address token, uint256 amount) external payable {
        userCollateral[msg.sender].amounts[token] -= amount;
        _requireOverCollateralized(
            userCollateral[msg.sender],
            userDebt[msg.sender]
        );

        if (!ERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    function repay(address token, uint256 amount) external payable {
        userDebt[msg.sender].amounts[token] -= amount;
        if (!ERC20(token).transferFrom(msg.sender, address(this), amount))
            revert TransferFailed();
    }

    function borrow(address token, uint256 amount) external payable {
        userDebt[msg.sender].amounts[token] += amount;
        _requireOverCollateralized(
            userCollateral[msg.sender],
            userDebt[msg.sender]
        );

        if (!ERC20(token).transfer(msg.sender, amount)) revert TransferFailed();
    }

    function _requireOverCollateralized(
        Position storage collateral,
        Position storage debt
    ) internal view {
        uint256 collateralValue = _positionValue(collateral);
        uint256 debtValue = _positionValue(debt);
        if (collateralValue < debtValue)
            revert UnderCollateralized(collateralValue, debtValue);
    }

    /// @return value position value denoted in USD amounts
    function _positionValue(Position storage pos)
        internal
        view
        returns (uint256 value)
    {
        value = pos.amounts[usd];
        value += (pos.amounts[ctf] * _getCtfPrice()) >> 112;
        value += (pos.amounts[pair] * _getPairPrice()) >> 112;
    }

    /// @return CTF price (denoted in USD) scaled by 2**112
    function _getCtfPrice() internal pure returns (uint256) {
        // external market price is 1000.0 USD per 1.0 CTF, determined by Oracle
        return 1_000 << 112;
    }

    /// @dev from https://github.com/AlphaFinanceLab/alpha-homora-v2-contract/blob/master/contracts/oracle/UniswapV2Oracle.sol
    /// read https://blog.alphafinance.io/fair-lp-token-pricing/ or https://cmichel.io/pricing-lp-tokens for more information
    /// cannot be manipulated by trading in the pool
    /// @return LP token price (denoted in USD) (TVL / totalSupply) scaled by 2**112
    function _getPairPrice() internal view returns (uint256) {
        uint256 totalSupply = IUniswapV2Pair(pair).totalSupply();
        (uint256 r0, uint256 r1, ) = IUniswapV2Pair(pair).getReserves();
        uint256 sqrtK = (SqrtMath.sqrt(r0 * r1) << 112) / totalSupply; // in 2**112
        uint256 priceCtf = 1_000 << 112; // in 2**112

        // fair lp price = 2 * sqrtK * sqrt(priceCtf * priceUsd) = 2 * sqrtK * sqrt(priceCtf)
        // sqrtK is in 2**112 and sqrt(priceCtf) is in 2**56. divide by 2**56 to return result in 2**112
        return (sqrtK * 2 * SqrtMath.sqrt(priceCtf)) / 2**56;
    }
}
