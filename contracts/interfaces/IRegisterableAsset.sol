// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

interface IRegisterableAsset {
  function assetName() external view returns (bytes32);
  function assetTotalSupply() external pure returns (uint256);
  function assetIsNFT() external pure returns (bool);
  function assetOperators() external view returns (address[] memory);
}
