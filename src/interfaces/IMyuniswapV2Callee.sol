// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IMyuniswapV2Callee {
    function myuniswapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) external;
}
