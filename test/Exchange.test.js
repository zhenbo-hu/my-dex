const { expect } = require("chai");
const { ethers } = require("hardhat");

const toWei = (value) => ethers.parseEther(value.toString());

const fromWei = (value) =>
  ethers.formatEther(typeof value === "string" ? value : value.toString());

describe("Exchange", () => {
  let owner;
  let user;
  let exchange;

  beforeEach(async () => {
    [owner, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("Token");
    token = await Token.deploy("Token", "TKN", toWei(1000000));
    await token.waitForDeployment();

    const Exchange = await ethers.getContractFactory("Exchange");
    exchange = await Exchange.deploy(token.getAddress());
    await exchange.waitForDeployment();
  });

  it("is deployed", async () => {
    expect(await exchange.waitForDeployment()).to.equal(exchange);
  });

  describe("addLiquidity", async () => {
    it("adds liquidity", async () => {
      console.log(await exchange.getAddress());
      const exchangeAddress = await exchange.getAddress();
      await token.approve(exchangeAddress, toWei(200));
      await exchange.addLiquidity(toWei(200), { value: toWei(100) });

      expect(await ethers.provider.getBalance(exchangeAddress)).to.equal(
        toWei(100)
      );
      expect(await exchange.getReserve()).to.equal(toWei(200));
    });
  });

  describe("getTokenAmount", async () => {
    it("returns correct token amount", async () => {
      await token.approve(exchange.getAddress(), toWei(2000));
      await exchange.addLiquidity(toWei(2000), { value: toWei(1000) });

      let tokensOut = await exchange.getTokenAmount(toWei(1));
      expect(fromWei(tokensOut)).to.equal("1.998001998001998001");

      tokensOut = await exchange.getTokenAmount(toWei(100));
      expect(fromWei(tokensOut)).to.equal("181.818181818181818181");

      tokensOut = await exchange.getTokenAmount(toWei(1000));
      expect(fromWei(tokensOut)).to.equal("1000.0");
    });
  });

  describe("getEthAmount", async () => {
    it("returns correct ether amount", async () => {
      await token.approve(exchange.getAddress(), toWei(2000));
      await exchange.addLiquidity(toWei(2000), { value: toWei(1000) });

      let ethOut = await exchange.getEthAmount(toWei(2));
      expect(fromWei(ethOut)).to.equal("0.999000999000999");

      ethOut = await exchange.getEthAmount(toWei(100));
      expect(fromWei(ethOut)).to.equal("47.619047619047619047");

      ethOut = await exchange.getEthAmount(toWei(2000));
      expect(fromWei(ethOut)).to.equal("500.0");
    });
  });

  describe("ethToTokenSwap", async () => {
    beforeEach(async () => {
      await token.approve(exchange.getAddress(), toWei(2000));
      await exchange.addLiquidity(toWei(2000), { value: toWei(1000) });
    });

    it("transfers at least min amount of tokens", async () => {
      const userBalanceBefore = await ethers.provider.getBalance(
        user.getAddress()
      );

      await exchange
        .connect(user)
        .ethToTokenSwap(toWei(1.99), { value: toWei(1) });

      const userBalanceAfter = await ethers.provider.getBalance(
        user.getAddress()
      );
      expect(fromWei(userBalanceAfter - userBalanceBefore)).to.equal(
        "-1.000065644144037532"
      );

      const userTokenBalance = await token.balanceOf(user.getAddress());
      expect(fromWei(userTokenBalance)).to.equal("1.998001998001998001");

      const exchangeEthBalance = await ethers.provider.getBalance(
        exchange.getAddress()
      );
      expect(fromWei(exchangeEthBalance)).to.equal("1001.0");

      const exchangeTokenBalance = await token.balanceOf(exchange.getAddress());
      expect(fromWei(exchangeTokenBalance)).to.equal("1998.001998001998001999");
    });

    it("fails when output amount is less than min amount", async () => {
      await expect(
        exchange.connect(user).ethToTokenSwap(toWei(2), { value: toWei(1) })
      ).to.be.revertedWith("insufficient output amount");
    });

    it("allows zero swaps", async () => {
      await exchange
        .connect(user)
        .ethToTokenSwap(toWei(0), { value: toWei(0) });

      const userTokenBalance = await token.balanceOf(user.getAddress());
      expect(fromWei(userTokenBalance)).to.equal("0.0");

      const exchangeEthBalance = await ethers.provider.getBalance(
        exchange.getAddress()
      );
      expect(fromWei(exchangeEthBalance)).to.equal("1000.0");

      const exchangeTokenBalance = await token.balanceOf(exchange.getAddress());
      expect(fromWei(exchangeTokenBalance)).to.equal("2000.0");
    });
  });

  describe("tokenToEthSwap", async () => {
    beforeEach(async () => {
      await token.transfer(user.getAddress(), toWei(2));
      await token.connect(user).approve(exchange.getAddress(), toWei(2));

      await token.approve(exchange.getAddress(), toWei(2000));
      await exchange.addLiquidity(toWei(2000), { value: toWei(1000) });
    });

    it("transfers at least min amount of tokens", async () => {
      const userBalanceBefore = await ethers.provider.getBalance(
        user.getAddress()
      );

      await exchange.connect(user).tokenToEthSwap(toWei(2), toWei(0.9));

      const userBalanceAfter = await ethers.provider.getBalance(
        user.getAddress()
      );
      expect(fromWei(userBalanceAfter - userBalanceBefore)).to.equal(
        "0.998953696554620848"
      );

      const userTokenBalance = await token.balanceOf(user.getAddress());
      expect(fromWei(userTokenBalance)).to.equal("0.0");

      const exchangeEthBalance = await ethers.provider.getBalance(
        exchange.getAddress()
      );
      expect(fromWei(exchangeEthBalance)).to.equal("999.000999000999001");

      const exchangeTokenBalance = await token.balanceOf(exchange.getAddress());
      expect(fromWei(exchangeTokenBalance)).to.equal("2002.0");
    });

    it("fails when output amount is less than min amount", async () => {
      await expect(
        exchange.connect(user).tokenToEthSwap(toWei(2), toWei(1.0))
      ).to.be.revertedWith("insufficient output amount");
    });

    it("allows zero swaps", async () => {
      await exchange.connect(user).tokenToEthSwap(toWei(0), toWei(0));

      const userBalance = await ethers.provider.getBalance(user.getAddress());
      expect(fromWei(userBalance)).to.equal("9999.998602262932444396");

      const userTokenBalance = await token.balanceOf(user.getAddress());
      expect(fromWei(userTokenBalance)).to.equal("2.0");

      const exchangeEthBalance = await ethers.provider.getBalance(
        exchange.getAddress()
      );
      expect(fromWei(exchangeEthBalance)).to.equal("1000.0");

      const exchangeTokenBalance = await token.balanceOf(exchange.getAddress());
      expect(fromWei(exchangeTokenBalance)).to.equal("2000.0");
    });
  });
});
