# Simple uniswap v1

交易所分为中心化交易所（CEX，像 Binance， Okx）和去中心化交易所（DEX，像 Uniswap）

## 中心化交易所原理简介

中心化交易所的核心是订单簿（order book），存储所有用户的买单和卖单，包含价格、数量等信息。

交易能够正常进行的保障是流动性（liquidity），即整个市场中所有可用的资产数量。

在 CEX 中，流动性存在于订单簿中。如果一个用户提交了一个卖单，那么就为市场提供了流动性；如果一个用户提交了一个买单，他希望市场具有流动性，否则交易就无法进行。

如果市场缺乏流动性，但是还存在着交易者希望进行交易，那么就需要做市商（market maker）。做市商是向市场提供流动性的、拥有大量各种资产的公司或个体。**通过提供流动性，做市商能够从交易中获得利润**。

## 去中心化交易所原理简介

去中心化交易同样需要流动性，并且也需要做市商向市场提供多种资产的流动性。然而，在 DEX 中这个过程无法被中心化地处理，我们需要一种**去中心化的做市商**方案。方案有多种，这里介绍 uniswap 所用到的自动做市商（Automated Market Maker，AMM）方案

### 自动做市商（AMM）

一个 AMM 是一套定义了如何管理流动性的智能合约。每个单独的交易对（例如 ETH/USDT）都是一个单独的智能合约，它存储了 ETH 和 USDT 资产并进行撮合交易。在这个合约中，我们可以将 ETH 兑换成 USDT 或者将 USDT 兑换成 ETH。

在 AMM 中，一个核心概念为**池子（pooling）**：每个合约都是一个存储流动性的池子，允许不同的用户（包括其他合约）在其中进行某种方式的交易。AMM 中有两种角色，**流动性提供者（LP）**以及**交易者（trader）**；这两者通过流动性池进行交互，而交互的方式由合约进行规定且不可更改。

![amm](./pic/amm_simplified.png)

这种交易方法与 CEX 的关键区别在于：**智能合约是完全自动化并且不受任何人控制的**。没有系统管理员，没有特权用户，一切都没有。这里只有 LP 和交易者，任何人都可以担任这两种角色（也可以同时），并且所有的算法都是公开的、程序规定的、不可更改的。

### 恒定函数做市商（Constant Function Market Makers）

恒定函数做市商（有时也被称为恒定乘积做市商）。尽管名字听起来很复杂，但是它的核心数学原理只是一个非常简单的公式：

$x*y=k$

$x$ 和 $y$ 是池子合约所拥有的两种资产的数目。$k$ 是它们的乘积，我们暂时不考虑它的实际值等于多少。

**为什么只有两种资产 x 和 y？** 每个 Uniswap 的池子仅包含两种 token。我们使用 x 和 y 来表示一个池子中的两种资产，其中 x 代表第一个 token，y 代表第二个 token。两种 token 的顺序（暂时）并不重要。

恒定函数做市商的原理是：**在每次交易前后，k 必须保持不变**。当用户进行交易，他们通常将一种类型的 token 放入池子（也即他们打算卖出的 token），并且将另一种类型的 token 移出池子（也即打算购买的 token）。这笔交易会改变池子中两种资产的数量，而上述原理表示，两种资产数目的乘积必须保持不变。我们之后还会在本书中看到许多次这个原理，这就是 Uniswap 的核心机制。

#### 交易函数

交易发生时的公式：

$(x + r\Delta x)(y-\Delta y) = k$

1. 一个池子包含一定数量的 token0 ($x$) 和一定数量的 token1 ($y$)
2. 当我们用 token0 购买 token1 的时候，一些 token0 被放入池子 ($\Delta x$)
3. 这个池子将给我们一定数量的 token1 作为交换 ($\Delta y$)
4. 池子也会从我们给出的 token0 中收取一定数量的手续费 ($r$)
5. 池子中 token0 的数量发生了变化 ($(x + r\Delta x)$)， token1 的数量也发生了变化 ($(y-\Delta y)$)
6. 二者的乘积保持不变，仍然为 $k$

简单来说，我们给了池子一定数量的 token0，然后获得了一定数量的 token1。这个池子的工作就是按照一个合理的价格，给予我们正确数量的 token1。我们可以得出以下结论：**池子决定了交易的价格**。

#### 价格

池子里 token 的价格是如何计算的？

由于 Uniswap 不同的池子对应不同的智能合约，同一个池子里的两种 token 互为计价标准进行定价。例如：在一个 ETH/USDC 的池子里，ETH 的价格用 USDC 作为标定，而 USDC 的价格用 ETH 作为标定。假设一个 ETH 的价格是 1000 USDC，那么一个 USDC 的价格就是 0.001 ETH。每一个池子都是如此，无论 token 是否为稳定币（例如，ETH/BTC 池）

池子中 token 的价格是由 token 的供给量决定的，也即池子中拥有该 token 的资产数目。token 的价格公式如下：

$P_x = \frac{y}{x}, P_y = \frac{x}{y}$

其中$P_x$和$P_y$是一个 token 相对于另一个 token 的价格

这个价格被称作 现货价格/现价， 它反映了当前的市场价。然而，交易实际成交的价格却并不是这个价格。现在我们再重新把需求方纳入考虑：

根据供求关系，**需求越高，价格越高**，这也是我们应当在去中心化交易中满足的性质。我们希望当需求很高的时候价格会升高，并且我们能够用池子里的资产数量来衡量需求：你希望从池子中获取某个 token 的数量越多，价格变动就越剧烈。我们再重新考虑上面这个公式：

$(x + r\Delta x)(y-\Delta y) = xy$

从这个公式中，我们能够推导出关于$\Delta x$和$\Delta y$的式子，这也意味着我们能够通过交易付出的 token 数目来计算出获得的 token 数目，反之亦然：

$\Delta y = \frac{yr\Delta x}{x+r\Delta y}$
$\Delta x = \frac{x\Delta y}{r(y-\Delta y)}$

这些公式就能够让我们重新计算价格。我们能够从$\Delta y$公式中求出获得 token 数量（当我们希望卖出 token 的数量为定值），并且从$\Delta x$的公式中求出需要提供的 token 数量（当我们购买 token 的数量为定值）。注意到，这里的公式是资产之间的关系，同时也把交易的数量(第一个公式中的$\Delta x$和第二个公式中的$\Delta y$)加入了计算。这是**同时考虑了供求双方的价格函数**。事实上，我们甚至并不需要去计算价格！（因为我们直接计算出了交易的结果）

#### 价格曲线

下面我们来把恒定乘积函数进行可视化来更好地理解其工作原理

恒定成绩函数的图像为二次双曲线：

![amm curve](./pic/the_curve.png)

横纵轴分别表示池子中两种代币的数量。每一笔交易的起始点都是曲线上与当前两种代币比例相对应的点。为了计算交易获得的 token 数量，我们需要找到曲线上的一个新的点，其横坐标值为$(x + r\Delta x)$，也即池子中现在 token0 的数量加上我们卖出的数量。y 轴上的变化量就是我们将会获得的 token1 的数量。

## Uniswap v1 特点

- 直接交易（一步交易）只有 ERC20 Token-Eth 交易对
- ERC20- ERC20 交易对通过 ERC20 Token-ETH 交易对链式完成（例如，A-B 交易对实际上是通过 A-ETH ETH-B 和 B-ETH ETH-A 完成的）

## Uniswap v1 核心代码

1. [ERC20 Token](./contracts/Token.sol)
2. [Exchange core](./contracts/Exchange.sol)
3. [Factory](./contracts/Factory.sol)
