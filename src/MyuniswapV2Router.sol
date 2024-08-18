// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./interfaces/IMyuniswapV2Factory.sol";
import "./interfaces/IMyuniswapV2Pair.sol";
import "./MyuniswapV2Library.sol";

// Router合约是相对Pair合约的更高级的存在，是大部分使用该swap合约的DApps的入口
// Router提供创建交易币对、添加流动性、移除流动性、计算价格等
contract MyuniswapV2Router {
    error ExcessiveInputAmount();
    error InsufficientAAmount();
    error InsufficientBAmount();
    error InsufficientOutputAmount();
    error SafeTransferFailed();

    IMyuniswapV2Factory factory;

    constructor(address factoryAddress) {
        factory = IMyuniswapV2Factory(factoryAddress);
    }

    // 添加流动性
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        // 若该交易币对不存在，则先通过factory合约创建该币对
        if (factory.pairs(tokenA, tokenB) == address(0)) {
            factory.createPair(tokenA, tokenB);
        }

        // 根据数量，计算对应应该用于加入流动性的token数量
        (amountA, amountB) = _calculateLiquidity(
            tokenA,
            tokenB,
            amountADesired,
            amountBDesired,
            amountAMin,
            amountBMin
        );

        address pairAddress = MyuniswapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );

        _safeTransferFrom(tokenA, msg.sender, pairAddress, amountA);
        _safeTransferFrom(tokenB, msg.sender, pairAddress, amountB);

        // 通过pair合约，添加流动性
        liquidity = IMyuniswapV2Pair(pairAddress).mint(to);
    }

    // 移除流动性
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to
    ) public returns (uint256 amountA, uint256 amountB) {
        address pair = MyuniswapV2Library.pairFor(
            address(factory),
            tokenA,
            tokenB
        );

        // 向币对合约发送LP token并销毁
        IMyuniswapV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (amountA, amountB) = IMyuniswapV2Pair(pair).burn(to);

        // 检查退回的token数量是否满足用户设定滑点的范围
        if (amountA < amountAMin) revert InsufficientAAmount();
        if (amountB < amountBMin) revert InsufficientBAmount();
    }

    // 精确交换，按照path提供的路径进行链式交换
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        // 根据path计算最终得到的数量
        amounts = MyuniswapV2Library.getAmountsOut(
            address(factory),
            amountIn,
            path
        );

        if (amounts[amounts.length - 1] < amountOutMin)
            revert InsufficientOutputAmount();

        _safeTransferFrom(
            (path[0]),
            msg.sender,
            MyuniswapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    // 交换函数，同样支持链式交换
    // 输入token数量只设定了最大值，并确定了输出token的数量
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) public returns (uint256[] memory amounts) {
        amounts = MyuniswapV2Library.getAmountsIn(
            address(factory),
            amountOut,
            path
        );

        if (amounts[amounts.length - 1] > amountInMax)
            revert ExcessiveInputAmount();

        _safeTransferFrom(
            path[0],
            msg.sender,
            MyuniswapV2Library.pairFor(address(factory), path[0], path[1]),
            amounts[0]
        );

        _swap(amounts, path, to);
    }

    // private function
    // 链式交换函数，按照所给的path，依次进行交换
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = MyuniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? MyuniswapV2Library.pairFor(
                    address(factory),
                    output,
                    path[i + 2]
                )
                : _to;
            IMyuniswapV2Pair(
                MyuniswapV2Library.pairFor(address(factory), input, output)
            ).swap(amount0Out, amount1Out, to, "");
        }
    }

    // 根据用户期望转移的token数量和期望的添加到流动池的最小数量，计算应该被添加到流动池的token数量
    // 由于在用户选择数量和实际处理交易间存在延迟，因此会导致用户失去一部分LP代币
    // 通过设定预计的数量和最小数量，降低这种损失
    function _calculateLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        (uint256 reserveA, uint256 reserveB) = MyuniswapV2Library.getReserves(
            address(factory),
            tokenA,
            tokenB
        );

        // 无流动性时，可直接按照用户期望的数量添加流动池 (amountADesired, amountBDesired)
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            // 已存在流动性，需要计算当下的添加token数量

            // 以amountADesired为基准，以当前流动池，计算可添加token B的数量
            uint256 amountBOptimal = MyuniswapV2Library.quote(
                amountADesired,
                reserveA,
                reserveB
            );

            // 如果amountBOptimal在用户期望的范围内时，可添加到流动池的token数量为(amountADesired, amountBOptimal)
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal <= amountBMin) revert InsufficientBAmount();
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                // 当amountBOptimal > amountBDesired时，需要再计算amountAOptimal，看是否能够满足用户需求
                // 如果能够满足，则可添加到流动池的token数量为(amountAOptimal, amountBDesired)

                uint256 amountAOptimal = MyuniswapV2Library.quote(
                    amountBDesired,
                    reserveB,
                    reserveA
                );
                assert(amountAOptimal <= amountADesired);

                if (amountAOptimal <= amountAMin) revert InsufficientAAmount();
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                to,
                value
            )
        );

        if (!success || (data.length != 0 && !abi.decode(data, (bool))))
            revert SafeTransferFailed();
    }
}
