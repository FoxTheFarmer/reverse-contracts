//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function getAmountsOut (uint256 _inputAmount, address[] memory swapPath) external returns( uint256[] memory ) ;
}
