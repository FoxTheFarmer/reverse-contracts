// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;

interface ITwapOracle {
    function consult(address token, uint256 amountIn) external view returns (uint256 amountOut);

    function update() external;
}