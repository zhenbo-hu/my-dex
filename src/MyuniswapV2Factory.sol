// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MyuniswapV2Pair.sol";
import "./interfaces/IMyuniswapV2Pair.sol";

contract MyuniswapV2Factory {
    error IdenticalAddresses();
    error PairExists();
    error ZeroAddress();

    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    mapping(address => mapping(address => address)) public pairs;
    address[] public allPairs;

    function createPair(
        address tokenA,
        address tokenB
    ) public returns (address pair) {
        if (tokenA == tokenB) revert IdenticalAddresses();

        // 确保同一个币对只会被生成一次Pair合约
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);

        if (token0 == address(0)) revert ZeroAddress();

        if (pairs[token0][token1] != address(0)) revert PairExists();

        bytes memory bytecode = type(MyuniswapV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));

        // 通过create2来生成MyuniswapV2Pair合约，可以提前确定生成的合约地址
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }

        IMyuniswapV2Pair(pair).initialize(token0, token1);

        pairs[token0][token1] = pair;
        pairs[token1][token0] = pair;
        allPairs.push(pair);

        emit PairCreated(token0, token1, pair, allPairs.length);
    }
}
