// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPancakeV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}

interface IPancakeswapV2Router {
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountInWEI,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

interface IPancakeswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInput(
        ExactInputParams calldata params
    ) external payable returns (uint256 amountOut);

    function WETH9() external pure returns (address);

    function factory() external pure returns (address);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract BlockAISwapPartial {
    struct ExecuteBuySellParams {
        address baseToken;
        address quoteToken;
        uint24 fee;
    }
    struct TradeStrategy {
        uint256[] buy;
        uint256[] sell;
    }
    address public owner;
    IPancakeswapV2Router public v2Router;
    IPancakeswapV3Router public v3Router;

    event EthDeposited(address indexed sender, uint256 amount);
    event EthWithdrawn(address indexed owner, uint256 amount);
    event ApproveToken(address indexed token, address router);
    event BuySellExecuted(
        address indexed token,
        uint256 ethSpent,
        uint256 tokensBought
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor(address v2RouterAddress, address v3RouterAddress) {
        owner = msg.sender;
        v2Router = IPancakeswapV2Router(v2RouterAddress);
        v3Router = IPancakeswapV3Router(v3RouterAddress);
    }

    receive() external payable {
        emit EthDeposited(msg.sender, msg.value);
    }

    function withdrawEth(uint256 _amount) external onlyOwner {
        require(address(this).balance >= _amount, "Insufficient balance");
        payable(owner).transfer(_amount);
        emit EthWithdrawn(owner, _amount);
    }

    function approveToken(address _tokenAddress) public {
        uint256 approveAmount = 10000000000000000000000000000000000;
        IERC20(_tokenAddress).approve(address(v2Router), approveAmount);
        IERC20(_tokenAddress).approve(address(v3Router), approveAmount);
    }

    function executeV2BuySell(
        ExecuteBuySellParams calldata params,
        TradeStrategy calldata strategy
    ) public payable {
        require(msg.sender.balance > 0, "Insufficient ETH balance");
        require(params.baseToken != address(0), "Invalid baseToken");
        require(params.quoteToken != address(0), "Invalid quoteToken");

        uint256 _ethAmount = msg.value;
        require(_ethAmount > 0, "No ETH sent");

        // Buy phase with strategy
        uint256 quoteTokenAmount = 0;
        for (uint256 i = 0; i < strategy.buy.length; i++) {
            uint256 buyAmount = (strategy.buy[i] * _ethAmount) / 10000;
            // Handle different paths based on whether baseToken or quoteToken is WETH
            if (params.baseToken == v2Router.WETH()) {
                // If baseToken is WETH, we swap ETH directly to quoteToken
                address[] memory buyPath = new address[](2);
                buyPath[0] = v2Router.WETH();
                buyPath[1] = params.quoteToken;

                uint256[] memory amounts = v2Router.swapExactETHForTokens{
                    value: buyAmount
                }(0, buyPath, address(this), block.timestamp + 15 minutes);

                quoteTokenAmount += amounts[amounts.length - 1];
            } else {
                // Standard case: ETH -> baseToken -> quoteToken
                address[] memory buyPath = new address[](3);
                buyPath[0] = v2Router.WETH();
                buyPath[1] = params.baseToken;
                buyPath[2] = params.quoteToken;

                uint256[] memory amounts = v2Router.swapExactETHForTokens{
                    value: buyAmount
                }(0, buyPath, address(this), block.timestamp + 15 minutes);

                quoteTokenAmount += amounts[amounts.length - 1];
            }
        }

        // Sell phase with strategy
        for (uint256 i = 0; i < strategy.sell.length; i++) {
            uint256 sellAmount = (strategy.sell[i] * quoteTokenAmount) / 10000;
            if (params.baseToken == v2Router.WETH()) {
                // If baseToken is WETH, we swap quoteToken -> WETH -> ETH

                address[] memory sellPath = new address[](2);
                sellPath[0] = params.quoteToken;
                sellPath[1] = v2Router.WETH();

                v2Router.swapExactTokensForETH(
                    sellAmount,
                    0,
                    sellPath,
                    msg.sender,
                    block.timestamp + 15 minutes
                );
            } else {
                address[] memory sellPath = new address[](3);
                sellPath[0] = params.quoteToken;
                sellPath[1] = params.baseToken;
                sellPath[2] = v2Router.WETH();

                v2Router.swapExactTokensForETH(
                    sellAmount,
                    0,
                    sellPath,
                    msg.sender,
                    block.timestamp + 15 minutes
                );
            }
        }
    }

    function executeBuySell(
        ExecuteBuySellParams calldata params,
        TradeStrategy calldata strategy
    ) external payable {
        require(msg.sender.balance > 0, "Insufficient ETH balance");
        require(params.baseToken != address(0), "Invalid baseToken");
        require(params.quoteToken != address(0), "Invalid quoteToken");

        uint256 _ethAmount = msg.value;
        require(_ethAmount > 0, "No ETH sent");

        if (params.fee == 0) {
            executeV2BuySell(params, strategy);
            return;
        }

        IPancakeV3Factory factory = IPancakeV3Factory(v3Router.factory());

        uint24[] memory feeTiers = new uint24[](3);
        feeTiers[0] = 500; // 0.05%
        feeTiers[1] = 2500; // 0.25%
        feeTiers[2] = 10000; // 1%

        uint24 wethBaseTokenFee = 500;
        for (uint256 i = 0; i < feeTiers.length; i++) {
            address pool = factory.getPool(
                v3Router.WETH9(),
                params.baseToken,
                feeTiers[i]
            );
            if (pool != address(0)) {
                wethBaseTokenFee = feeTiers[i];
                break;
            }
        }

        bytes memory buyPath;
        if (params.baseToken == v3Router.WETH9()) {
            buyPath = abi.encodePacked(
                params.baseToken,
                params.fee,
                params.quoteToken
            );
        } else {
            buyPath = abi.encodePacked(
                v3Router.WETH9(),
                wethBaseTokenFee,
                params.baseToken,
                params.fee,
                params.quoteToken
            );
        }

        uint256 quoteTokenAmount = 0;
        for (uint256 i = 0; i < strategy.buy.length; i++) {
            uint256 buyAmount = (strategy.buy[i] * _ethAmount) / 10000;
            IPancakeswapV3Router.ExactInputParams memory buyParams = IPancakeswapV3Router.ExactInputParams({
                    path: buyPath,
                    recipient: address(this),
                    deadline: block.timestamp + 15 minutes,
                    amountIn: buyAmount,
                    amountOutMinimum: 0
                });
            v3Router.exactInput{value: strategy.buy[i]}(buyParams);
            quoteTokenAmount += v3Router.exactInput{value: buyAmount}(
                buyParams
            );
        }

        bytes memory sellPath;
        if (params.baseToken == v3Router.WETH9()) {
            sellPath = abi.encodePacked(
                params.quoteToken,
                params.fee,
                params.baseToken
            );
        } else {
            sellPath = abi.encodePacked(
                params.quoteToken,
                params.fee,
                params.baseToken,
                wethBaseTokenFee,
                v3Router.WETH9()
            );
        }

        for (uint256 i = 0; i < strategy.sell.length; i++) {
            uint256 sellAmount = (strategy.sell[i] * quoteTokenAmount) / 10000;
            IPancakeswapV3Router.ExactInputParams
                memory sellParams = IPancakeswapV3Router.ExactInputParams({
                    path: sellPath,
                    recipient: msg.sender,
                    deadline: block.timestamp + 15 minutes,
                    amountIn: sellAmount,
                    amountOutMinimum: 0
                });
            v3Router.exactInput(sellParams);
        }
    }
}
