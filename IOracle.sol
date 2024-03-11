// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IOracle {
    function getPrice() external view returns (uint256);
}
