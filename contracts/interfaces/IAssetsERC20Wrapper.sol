// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "./IAssets.sol";

import "hardhat/console.sol";

interface IAssetsERC20Wrapper is IERC20 {

    function unwrap(address account, address to, uint256 amount) external;
    
}
