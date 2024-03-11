// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./interfaces/IOracle.sol";
import "./libraries/Decimals.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract OneUsdOracleLocal is IOracle {
    address pair;
    address numerator;
    address denominator;

    /**
     * USDT - One Pair Info
     */
    constructor(
        address pair_,
        address numerator_,
        address denominator_
    ) {
        pair = pair_;
        numerator = numerator_;
        denominator = denominator_;
    }

    /**
     * Returns the latest price
     */
    function getPrice() public view override returns (uint256) {
        uint8 _numeratorDecimals = IERC20Metadata(numerator).decimals();
        uint8 _denominatorDecimals = IERC20Metadata(denominator).decimals();

        uint256 _numeratorBalance = IERC20(numerator).balanceOf(pair);
        uint256 _denominatorBalance = IERC20(denominator).balanceOf(pair);

        (
            uint256 _numeratorBalanceFormatted,
            uint256 _denominatorBalanceFormatted,

        ) = Decimals.formatToBiggerDecimals(
                _numeratorDecimals,
                _denominatorDecimals,
                _numeratorBalance,
                _denominatorBalance
            );

        return
            Decimals.divWithPrecision(
                _numeratorBalanceFormatted,
                _denominatorBalanceFormatted,
                8
            );
    }
}
