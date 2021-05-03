// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

library Constants {
  bytes32 constant PRESTIGE_ASSET_NAME = "prestige";

  function prestigeAssetName() internal pure returns(bytes32){
    return PRESTIGE_ASSET_NAME;
  }
}
