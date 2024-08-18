// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "solmate/tokens/ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112X112.sol";
import "./interfaces/IMyuniswapV2Callee.sol";

interface IERC20 {
    function balanceOf(address) external returns (uint256);

    function transfer(address to, uint256 amount) external;
}

error AlreadyInitialized();
error BalanceOverflow();
error InsufficientInputAmount();
error InsufficientLiquidity();
error InsufficientLiquidityMinted();
error InsufficientLiquidityBurned();
error InsufficientOutputAmount();
error InvalidK();
error TransferFailed();

contract MyuniswapV2Pair is ERC20, Math {
    using UQ112x112 for uint224;

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    address public token0;
    address public token1;

    // 存储优化，通过两个uint112和一个uint32，共256bit 32字节，可以存储在同一个存储插槽中，并被EVM一次访问同时读取
    // 跟踪流动池中的token储备数量
    uint112 private reserve0;
    uint112 private reserve1;
    // 时间戳，用于记录token变动
    uint32 private blockTimestampLast;

    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;

    bool private isEntered;

    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address to
    );
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Sync(uint256 reserve0, uint256 reserve1);
    event Swap(
        address indexed sender,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );

    // 防止重入攻击
    modifier noReentrant() {
        require(!isEntered);
        isEntered = true;

        _;

        isEntered = false;
    }

    constructor() ERC20("MyuniswapV2 Pair", "MUNIV2", 18) {}

    function initialize(address _token0, address _token1) public {
        if (token0 != address(0) || token1 != address(0))
            revert AlreadyInitialized();

        token0 = _token0;
        token1 = _token1;
    }

    // 添加流动性
    function mint(address to) public returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        // 用户将token1和token2转移至合约地址
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        // 首次添加流动性时，根据提供的token0数量和token1数量的几何平均值计算初始LP，
        // 其中减去MINIMUM_LIQUIDITY，防止LP成本过高，从而拒绝小型流动性提供者
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            // 非首次添加流动性时，计算LP（取最小值，惩罚提供不平衡流动性/试图操纵价格的行为）
            liquidity = Math.min(
                (amount0 * totalSupply) / _reserve0,
                (amount1 * totalSupply) / _reserve1
            );
        }

        if (liquidity <= 0) revert InsufficientLiquidityMinted();

        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Mint(to, amount0, amount1);
    }

    // 移除流动性
    function burn(
        address to
    ) public returns (uint256 amount0, uint256 amount1) {
        // 用户将LP token转移至合约地址
        uint256 liquidity = balanceOf[address(this)];
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        // 计算对应LP token数量对应的token0和token1数量
        amount0 = (liquidity * balance0) / totalSupply;
        amount1 = (liquidity * balance1) / totalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientLiquidityBurned();

        // 燃烧掉LP token并将对应的token0和token1转到用户提供的地址
        _burn(address(this), liquidity);
        _safeTransfer(token0, to, amount0);
        _safeTransfer(token1, to, amount1);

        balance0 = IERC20(token0).balanceOf(address(this));
        balance1 = IERC20(token1).balanceOf(address(this));

        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _update(balance0, balance1, _reserve0, _reserve1);

        emit Burn(msg.sender, amount0, amount1, to);
    }

    // token交换，入参包含了两个token的数量，因此只需要一个交换函数即可支持双向交换
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) public noReentrant {
        if (amount0Out == 0 && amount1Out == 0)
            revert InsufficientOutputAmount();

        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();

        if (amount0Out > _reserve0 || amount1Out > _reserve1)
            revert InsufficientLiquidity();

        // 闪电贷，乐观的将token发送到地址
        if (amount0Out > 0) _safeTransfer(token0, to, amount0Out);
        if (amount1Out > 0) _safeTransfer(token1, to, amount1Out);
        // 调用to地址的回调函数
        if (data.length > 0) {
            IMyuniswapV2Callee(to).myuniswapV2Call(
                msg.sender,
                amount0Out,
                amount1Out,
                data
            );
        }

        // 获取用户转移至合约地址的token数量（注定有其中一个为0），同时也确定了交换方向
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));

        uint256 amount0In = balance0 > reserve0 - amount0Out
            ? balance0 - (reserve0 - amount0Out)
            : 0;
        uint256 amount1In = balance1 > reserve1 - amount1Out
            ? balance1 - (reserve1 - amount1Out)
            : 0;

        if (amount0In == 0 && amount1In == 0) revert InsufficientInputAmount();

        // 包含交易手续费
        uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
        uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);

        // 检查闪电贷归还是否成功
        if (
            balance0Adjusted * balance1Adjusted <
            uint256(_reserve0) * uint256(_reserve1) * (1000 ** 2)
        ) revert InvalidK();

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0Out, amount1Out, to);
    }

    function sync() public {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves();
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            _reserve0,
            _reserve1
        );
    }

    function getReserves() public view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, blockTimestampLast);
    }

    // private functions
    function _update(
        uint256 balance0,
        uint256 balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max)
            revert BalanceOverflow();

        unchecked {
            uint32 timeElapsed = uint32(block.timestamp) - blockTimestampLast;

            if (timeElapsed > 0 && _reserve0 > 0 && _reserve1 > 0) {
                price0CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                    timeElapsed;
                price1CumulativeLast +=
                    uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                    timeElapsed;
            }
        }

        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = uint32(block.timestamp);

        emit Sync(reserve0, reserve1);
    }

    // 安全转账，通过call方法能够获取调用是否成功的bool，实现对合约更加精细准确的控制
    function _safeTransfer(address token, address to, uint256 value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, value)
        );

        if (!success || (data.length != 0 && !abi.decode(data, (bool))))
            revert TransferFailed();
    }
}
