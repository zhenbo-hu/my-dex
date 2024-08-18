// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MyuniswapV2Pair.sol";

contract Flashloaner {
    error InsufficientFlashLoanAmount();

    uint256 expectedLoanAmount;

    function flashloan(
        address pairAddress,
        uint256 amount0Out,
        uint256 amount1Out,
        address tokenAddress
    ) public {
        if (amount0Out > 0) {
            expectedLoanAmount = amount0Out;
        }

        if (amount1Out > 0) {
            expectedLoanAmount = amount1Out;
        }

        MyuniswapV2Pair(pairAddress).swap(
            amount0Out,
            amount1Out,
            address(this),
            abi.encode(tokenAddress)
        );
    }

    function myunsiwapV2Call(
        address sender,
        uint256 amount0Out,
        uint256 amount1Out,
        bytes calldata data
    ) public {
        address tokenAddress = abi.encode(data, (address));
        uint256 balance = IERC20(tokenAddress).balanceOf(address(this));

        if (balance < expectedLoanAmount) revert InsufficientFlashLoanAmount();

        IERC20(tokenAddress).transfer(msg.sender, balance);
    }
}
