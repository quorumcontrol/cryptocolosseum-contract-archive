// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAssets.sol";
import "./interfaces/IRegisterableAsset.sol";
import "./EnumerableMap.sol";
import "./meta/EIP712MetaTransaction.sol";

import "hardhat/console.sol";

contract Trophy is Ownable, IRegisterableAsset, EIP712MetaTransaction {
  using SafeMath for uint256;
  using EnumerableMap for EnumerableMap.Map;

  bytes32 immutable ASSET_NAME;
  uint256 constant TOTAL_SUPPLY = 2**38;

  IAssets immutable public assets;

  struct Metadata {
    string name;
    EnumerableMap.Map properties;
  }

  mapping(uint256 => Metadata) private _metadata;

  constructor(
    address assetsAddress,
    bytes32 name
   ) public EIP712MetaTransaction("Trophy", "1") {
    assets = IAssets(assetsAddress);
    ASSET_NAME = name;
  }

  function assetName() override public view returns (bytes32) {
    return ASSET_NAME;
  }

  function assetTotalSupply() override public pure returns (uint256) {
    return TOTAL_SUPPLY;
  }

  function assetIsNFT() override public pure returns (bool) {
    return true;
  }

  function assetOperators() override public view returns (address[] memory) {
    address[] memory operators = new address[](1);
    operators[0] = address(this);
    return operators;
  }

  function idRange() public view returns (uint256, uint256) {
    return assets.idRange(ASSET_NAME);
  }

  function mint(
    address account,
    string  memory name,
    uint256 tournamentID,
    uint256 gladiatorID
  ) external onlyOwner returns (uint256) {
    uint256[] memory ids = assets.mint(account, ASSET_NAME, 1, abi.encodePacked(gladiatorID));
    uint256 id = ids[0];

    Metadata storage metadata = _metadata[id];
    metadata.name = name;
 
    EnumerableMap.Map storage _properties = metadata.properties;

    _properties.set("tournamentID", bytes32(tournamentID));
    _properties.set("gladiatorID", bytes32(gladiatorID));
    _properties.set("createdAt", bytes32(block.timestamp));

    return id;
  }

  function exists(
    uint256 id
  ) external view returns (bool) {
    return assets.exists(ASSET_NAME, id);
  }

  function name(
    uint256 id
  ) external view returns (string memory) {
    return _metadata[id].name;
  }

  function properties(
    uint256 id
  ) external view returns (EnumerableMap.MapEntry[] memory) {
    EnumerableMap.Map storage _properties = _metadata[id].properties;
    uint256 propsLength = _properties.length(); 
    EnumerableMap.MapEntry[] memory propertyPairs = new EnumerableMap.MapEntry[](propsLength);
    for (uint256 i = 0; i < propsLength; i++) {
      (bytes32 k, bytes32 v) = _properties.at(i);
      propertyPairs[i].key = k;
      propertyPairs[i].value = v;
    }
    return propertyPairs;
  }

  function getProperty(
    uint256 id,
    bytes32 key
  ) external view returns (bytes32) {
    EnumerableMap.Map storage _properties = _metadata[id].properties;
    return _properties.get(key);
  }

  function _msgSender() internal view override(Context,EIP712MetaTransaction) returns (address payable) {
    return EIP712MetaTransaction.msgSender();
  }
}
