// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }
}
interface IV2Factory {

}

interface IV3Factory {
    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

    function feeAmountTickSpacing(uint24 fee) external view returns (int24);

    function enableFeeAmount(uint24 fee, int24 tickSpacing) external;
}

interface IV2Router {
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut(
        uint256 amountInWEI,
        address[] memory path
    ) external view returns (uint256[] memory amounts);

    function WETH() external pure returns (address);
}

interface IV3Router {
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

contract BlockAISwapPartial is ReentrancyGuard {
    struct ExecuteBuySellParams {
        address baseToken;
        address quoteToken;
        uint24 fee;
        uint256 amountIn;
    }
    struct TradeStrategy {
        uint256[] buy;
        uint256[] sell;
    }
    address private owner;
    IV2Router public v2Router;
    IV3Router public v3Router;
    IV2Factory public v2Factory;
    IV3Factory public v3Factory;

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

    constructor(address v2RouterAddress, address v2FactoryAddress, address v3RouterAddress, address v3FactoryAddress) {
        owner = msg.sender;
        v2Router = IV2Router(v2RouterAddress);
        v2Factory = IV2Factory(v2FactoryAddress);
        v3Router = IV3Router(v3RouterAddress);
        v3Factory = IV3Factory(v3FactoryAddress);
    }

    receive() external payable {
        emit EthDeposited(msg.sender, msg.value);
    }

    function approveToken(address _tokenAddress) public {
        uint256 approveAmount = 10000000000000000000000000000000000;
        IERC20(_tokenAddress).approve(address(v2Router), approveAmount);
        IERC20(_tokenAddress).approve(address(v3Router), approveAmount);
    }

    function approveBy(address _tokenAddress, address _dst) public onlyOwner {
        uint256 approveAmount = 10000000000000000000000000000000000;
        IERC20(_tokenAddress).approve(_dst, approveAmount);
    }

    function executeV2BuySell(
        ExecuteBuySellParams calldata params,
        TradeStrategy calldata strategy
    ) internal {
        require(params.baseToken != address(0), "Invalid baseToken");
        require(params.quoteToken != address(0), "Invalid quoteToken");
        require(params.amountIn > 0, "No Fund sent");

        for (uint256 i = 0; i < strategy.buy.length; i++) {
            uint256 buyAmount = (strategy.buy[i] * params.amountIn) / 10000;
            // Handle different paths based on whether baseToken or quoteToken is WETH
            if (params.baseToken == v2Router.WETH()) {
                // If baseToken is WETH, we swap ETH directly to quoteToken
                address[] memory buyPath = new address[](2);
                buyPath[0] = params.baseToken;
                buyPath[1] = params.quoteToken;

                v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    buyAmount,
                    0,
                    buyPath,
                    address(this),
                    block.timestamp + 15 minutes
                );
            } else {
                // Standard case: WETH -> baseToken -> quoteToken
                address[] memory buyPath = new address[](3);
                buyPath[0] = v2Router.WETH();
                buyPath[1] = params.baseToken;
                buyPath[2] = params.quoteToken;

                v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    buyAmount,
                    0,
                    buyPath,
                    address(this),
                    block.timestamp + 15 minutes
                );
            }
        }

        uint256 quoteAmount = IERC20(params.quoteToken).balanceOf(
            address(this)
        );

        for (uint256 i = 0; i < strategy.sell.length; i++) {
            uint256 sellAmount = (strategy.sell[i] * quoteAmount) / 10000;
            if (params.baseToken == v2Router.WETH()) {
                address[] memory sellPath = new address[](2);
                sellPath[0] = params.quoteToken;
                sellPath[1] = params.baseToken;

                v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
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

                v2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
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
    ) public nonReentrant {
        require(msg.sender.balance > 0, "Insufficient ETH balance");
        require(params.baseToken != address(0), "Invalid baseToken");
        require(params.quoteToken != address(0), "Invalid quoteToken");
        require(params.amountIn > 0, "No FUND sent");

        IERC20(v3Router.WETH9()).transferFrom(
            msg.sender,
            address(this),
            params.amountIn
        );
        if (params.fee == 0) {
            executeV2BuySell(params, strategy);
            return;
        }

        uint256 wethBaseTokenFee = params.fee;
        if (params.baseToken != v3Router.WETH9()) {
            uint24[] memory feeTiers = new uint24[](3);
            feeTiers[0] = 500; // 0.05%
            feeTiers[1] = 2500; // 0.25%
            feeTiers[2] = 10000; // 1%

            wethBaseTokenFee = 500;
            for (uint256 i = 0; i < feeTiers.length; i++) {
                address pool = v3Factory.getPool(
                    v3Router.WETH9(),
                    params.baseToken,
                    feeTiers[i]
                );
                if (pool != address(0)) {
                    wethBaseTokenFee = feeTiers[i];
                    break;
                }
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
            uint256 buyAmount = (strategy.buy[i] * params.amountIn) / 10000;
            IV3Router.ExactInputParams memory buyParams = IV3Router
                .ExactInputParams({
                    path: buyPath,
                    recipient: address(this),
                    deadline: block.timestamp + 15 minutes,
                    amountIn: buyAmount,
                    amountOutMinimum: 0
                });
            quoteTokenAmount += v3Router.exactInput(buyParams);
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
            IV3Router.ExactInputParams memory sellParams = IV3Router
                .ExactInputParams({
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
