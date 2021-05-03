// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IAssets.sol";
import "./interfaces/IRegisterableAsset.sol";
import "./EnumerableMap.sol";
import "./EnumerableStringMap.sol";
import "./Constants.sol";

import "hardhat/console.sol";

contract Faction is IRegisterableAsset, ERC1155Receiver {
  using SafeMath for uint256;
  using EnumerableMap for EnumerableMap.Map;
  using EnumerableStringMap for EnumerableStringMap.Map;
  using EnumerableSet for EnumerableSet.UintSet;

  bytes32 constant ASSET_NAME = "faction";
  uint256 constant TOTAL_SUPPLY = 2**24;

  uint256 constant ASSET_DECIMALS = 10**18;

  IAssets immutable public assets;

  // A little oddly but these are stored as the id +1 which is why this is private
  // this allows us to check for existence by looking at 0 which otherwise we could not (since 0 is a valid token id)
  mapping(string => uint256) private _byName; // name => id of token + 1

  struct Metadata {
    string name;
    EnumerableMap.Map properties;
    EnumerableStringMap.Map extendedProperties;
  }

  mapping(uint256 => Metadata) private _metadata;

  mapping(uint256 => EnumerableSet.UintSet) private _inventory;

  mapping(uint256 => mapping(uint256 => uint256)) private _balances;

  constructor(address assetsAddress) {
    assets = IAssets(assetsAddress);
  }

  function byName(string calldata name) public view returns (uint id) {
    id = _byName[name];
    if (id == 0) {
      return id;
    }
    return id - 1;
  }

  function assetName() override public pure returns (bytes32) {
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
    string calldata name,
    EnumerableMap.MapEntry[] calldata properties,
    EnumerableStringMap.MapEntry[] calldata extendedProperties
  ) external returns (uint256) {
    require(_byName[name] == 0, "Name already taken");

    uint256[] memory ids = assets.mint(account, ASSET_NAME, 1, "");
    uint256 id = ids[0];

    Metadata storage metadata = _metadata[id];
    metadata.name = name;

    EnumerableMap.Map storage _properties = metadata.properties;
    EnumerableStringMap.Map storage _extendedProperties = metadata.extendedProperties;

    for (uint i; i < properties.length; i++) {
      _properties.set(properties[i].key, properties[i].value);
    }

    for (uint i; i < extendedProperties.length; i++) {
      _extendedProperties.set(extendedProperties[i].key, extendedProperties[i].value);
    }

    _properties.set("createdAt", bytes32(block.timestamp));

    _byName[name] = id + 1;

    return id;
  }

  function exists(
    uint256 id
  ) public view returns (bool) {
    return assets.exists(ASSET_NAME, id);
  }

  function name(
    uint256 id
  ) external view returns (string memory) {
    return _metadata[id].name;
  }

  function prestige(
    uint256 id
  ) external view returns (uint256) {
    (uint256 prestigeTokenID,) = assets.idRange(Constants.prestigeAssetName());
    return _balances[id][prestigeTokenID];
  }

  function properties(
    uint256 id
  ) external view returns (EnumerableMap.MapEntry[] memory) {
    EnumerableMap.Map storage _properties = _metadata[id].properties;
    uint256 propsLength = _properties.length(); 
    EnumerableMap.MapEntry[] memory propertyPairs = new EnumerableMap.MapEntry[](propsLength);
    for (uint256 i = 0; i < propsLength; i++) {
      (bytes32 k, bytes32 v) = _properties.at(i);
      propertyPairs[i] = EnumerableMap.MapEntry({
        key: k,
        value: v
      });
    }
    return propertyPairs;
  }

  function getProperty(
    uint256 id,
    bytes32 key
  ) external view returns (bytes32) {
    return _metadata[id].properties.get(key);
  }
  
  function extendedProperties(
    uint256 id
  ) external view returns (EnumerableStringMap.MapEntry[] memory) {
    EnumerableStringMap.Map storage _extendedProperties = _metadata[id].extendedProperties;
    uint256 propsLength = _extendedProperties.length(); 
    EnumerableStringMap.MapEntry[] memory propertyPairs = new EnumerableStringMap.MapEntry[](propsLength);
    for (uint256 i = 0; i < propsLength; i++) {
      (bytes32 k, string memory v) = _extendedProperties.at(i);
      propertyPairs[i] = EnumerableStringMap.MapEntry({
        key: k,
        value: v
      });
    }
    return propertyPairs;
  }

  function getExtendedProperty(
    uint256 id,
    bytes32 key
  ) external view returns (string memory) {
    return _metadata[id].extendedProperties.get(key);
  }

  function inventory(
    uint256 id
  ) external view returns (uint256[] memory) {
    EnumerableSet.UintSet storage set = _inventory[id];
    uint256[] memory ids = new uint256[](set.length());
    for (uint256 i = 0; i < ids.length; i++) {
      ids[i] = set.at(i);
    }
    return ids;
  }

  function balances(
    uint256 id
  ) external view returns (uint256[] memory) {
    EnumerableSet.UintSet storage set = _inventory[id];
    uint256[] memory ret = new uint256[](set.length());
    for (uint256 i = 0; i < ret.length; i++) {
      ret[i] = _balances[id][set.at(i)];
    }
    return ret;
  }

  function balanceOf(
    uint256 id,
    uint256 tokenID
  ) external view returns (uint256) {
    return _balances[id][tokenID];
  }

  function onERC1155Received(
    address operator,
    address from,
    uint256 id,
    uint256 value,
    bytes calldata data
  ) external override returns(bytes4) {
    uint256[] memory ids = new uint256[](1);
    uint256[] memory values = new uint256[](1);
    ids[0] = id;
    values[0] = value;
    onERC1155BatchReceived(operator, from, ids, values, data);
    return IERC1155Receiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address operator,
    address from,
    uint256[] memory ids,
    uint256[] memory values,
    bytes calldata data // abi.encoded (uint256 gladiatorID)
  ) public override returns(bytes4) {
    require(msg.sender == address(assets), "Gladiator can only receive items from Assets contract");

    (uint256 gladiatorID) = abi.decode(data, (uint256));
    require(exists(gladiatorID), "gladiator does not exist");

    EnumerableSet.UintSet storage gladiatorInventory = _inventory[gladiatorID];
    for (uint i = 0; i < ids.length; i++) {
      gladiatorInventory.add(ids[i]);
      _balances[gladiatorID][ids[i]] += values[i];
    }

    return IERC1155Receiver.onERC1155BatchReceived.selector;
  }
}
