// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IExchange {
    function ethToTokenSwap(uint256 _minTokens) external payable;

    function ethToTokenTransfer(
        uint256 _minTokens,
        address _recipient
    ) external payable;
}

interface IFactory {
    function getExchange(address _tokenAddress) external returns (address);
}

contract Exchange is ERC20 {
    address public factoryAddress;
    address public tokenAddress;

    constructor(address _token) ERC20("Myswap-V1", "My-V1") {
        require(_token != address(0), "invalid token address");

        factoryAddress = msg.sender;
        tokenAddress = _token;
    }

    // eth -> token交换
    function ethToTokenSwap(uint256 _minTokens) public payable {
        ethToToken(_minTokens, msg.sender);
    }

    // token -> eth交换
    function tokenToEthSwap(uint256 _tokensSold, uint256 _minEth) public {
        uint256 ethBought = getEthAmount(_tokensSold);

        require(ethBought >= _minEth, "insufficient output amount");

        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokensSold
        );
        payable(msg.sender).transfer(ethBought);
    }

    // token A -> token B 交换
    // 1. token A -> eth 交换
    // 2. eth -> token B 交换
    function tokenToTokenSwap(
        uint256 _tokenSold,
        uint256 _minTokensBought,
        address _tokenAddress
    ) public {
        address exchangeAddress = IFactory(factoryAddress).getExchange(
            _tokenAddress
        );

        require(
            exchangeAddress != address(this) && exchangeAddress != address(0),
            "invalid exchange address"
        );

        // 卖掉token A，并计算得到的eth
        uint256 ethBought = getEthAmount(_tokenSold);
        IERC20(tokenAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenSold
        );

        // 将得到的eth交换为token B并转账给用户
        IExchange(exchangeAddress).ethToTokenTransfer{value: ethBought}(
            _minTokensBought,
            msg.sender
        );
    }

    // 用于 token A -> token B 交换的中间步骤
    function ethToTokenTransfer(
        uint256 _minTokens,
        address _recipient
    ) public payable {
        ethToToken(_minTokens, _recipient);
    }

    // 添加流动性
    // 1.1 流动性池为空时，可按照所提供的token和eth比例直接添加，并以eth数量为流动性
    // 1.2 流动性池不为空时，首先按照当前比例计算所提供的token和eth是否能够满足比例，并按照比例计算流动性，然后添加进流动池
    // 2. 根据提供的流动性，mint相应数量的LP token给流动性提供者
    function addLiquidity(uint _tokenAmount) public payable returns (uint256) {
        require(
            _tokenAmount > 0 && msg.value > 0,
            "invalid token or eth amount!"
        );

        IERC20 token = IERC20(tokenAddress);

        if (getReserve() == 0) {
            token.transferFrom(msg.sender, address(this), _tokenAmount);

            _mint(msg.sender, msg.value);

            return msg.value;
        } else {
            uint256 ethReserve = address(this).balance - msg.value;
            uint256 tokenReserve = getReserve();
            uint256 tokenAmount = (msg.value * tokenReserve) / ethReserve;

            require(_tokenAmount >= tokenAmount, "insufficient token amount!");

            token.transferFrom(msg.sender, address(this), tokenAmount);

            uint256 liquidity = (totalSupply() * msg.value) / ethReserve;
            _mint(msg.sender, liquidity);

            return liquidity;
        }
    }

    // 移除流动性
    // 1. 检查是否为流动性提供者，且想取走的流动性是有效的
    // 2. 根据当前流动性池，计算输入的LP token对应的token和eth数量
    // 3. 燃烧掉对应数量的LP token
    // 4. 将token和eth相应transfer给用户
    function removeLiquidity(
        uint256 _amount
    ) public returns (uint256, uint256) {
        require(balanceOf(msg.sender) > 0, "insufficient liquidity supporter");
        require(
            _amount > 0 && _amount <= balanceOf(msg.sender),
            "invalid amount"
        );

        uint256 ethAmount = (address(this).balance * _amount) / totalSupply();
        uint256 tokenAmount = (getReserve() * _amount) / totalSupply();

        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(ethAmount);
        IERC20(tokenAddress).transfer(msg.sender, tokenAmount);

        return (ethAmount, tokenAmount);
    }

    function getReserve() public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(address(this));
    }

    // 根据想卖掉的eth数量，计算对应的token数量
    function getTokenAmount(uint256 _ethSold) public view returns (uint256) {
        require(_ethSold > 0, "ethSold is too small");

        uint256 tokenReserve = getReserve();

        return
            getAmount(_ethSold, address(this).balance - _ethSold, tokenReserve);
    }

    // 根据想卖掉的token数量，计算对应的eth数量
    function getEthAmount(uint256 _tokenSold) public view returns (uint256) {
        require(_tokenSold > 0, "tokenSold is too small");

        uint256 tokenReserve = getReserve();

        return getAmount(_tokenSold, tokenReserve, address(this).balance);
    }

    // 根据amm的恒定乘积公式和输入参数计算交换后的token或eth数量
    function getAmount(
        uint256 inputAmount,
        uint256 inputReserve,
        uint256 outputReserve
    ) private pure returns (uint256) {
        require(inputReserve > 0 && outputReserve > 0, "invalid reserves");

        uint256 inputAmountWithFee = inputAmount * 99; // 1% trading fee
        uint256 numerator = inputAmountWithFee * outputReserve;
        uint256 denominator = (inputReserve * 100) + inputAmountWithFee;

        return numerator / denominator;
    }

    // 该函数是为了解决在tokenToTokenSwap时，如果没有recipient参数，直接将token B转给了exchange合约的问题
    function ethToToken(uint256 _minTokens, address recipient) private {
        uint256 tokensBought = getTokenAmount(msg.value);

        require(tokensBought >= _minTokens, "insufficient output amount");

        IERC20(tokenAddress).transfer(recipient, tokensBought);
    }
}
