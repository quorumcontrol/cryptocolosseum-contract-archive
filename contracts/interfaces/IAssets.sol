// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IAssets is IERC1155 {
  function mint(
    address account,
    bytes32 name,
    uint256 amount,
    bytes memory data
  ) external returns(uint256[] memory);
  
  function forge(
    address account,
    uint id,
    uint amount,
    bytes memory data
  ) external returns (bool);

  function burn(
    address account,
    bytes32 name,
    uint256 amount
  ) external;

  function isOwner(
    address account,
    uint256 id
  ) external view returns(bool);

  function isApprovedOrOwner(
    address account,
    address operator,
    uint256 id
  ) external view returns(bool);

  function nameForID(
    uint256 id
  ) external view returns(bytes32);

  function idRange(
    bytes32 name
  ) external view returns (uint256, uint256);

  function exists(
    bytes32 name,
    uint256 id
  ) external view returns (bool);

  function totalSupply(
    bytes32 name
  ) external view returns (uint256);

  function currentSupply(
    bytes32 name
  ) external view returns (uint256);

  function accountTokens(
    address account
  ) external view returns (uint256[] memory);
}
