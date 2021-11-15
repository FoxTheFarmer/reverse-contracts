// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IReverseum {
    function transferTo(
        address _token,
        address _receiver,
        uint256 _amount
    ) external;
    function fundBalance
    (
        address _token
    ) external view returns (uint256) ;

}
