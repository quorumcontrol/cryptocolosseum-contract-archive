// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

import "./meta/EIP712MetaTransaction.sol";
import "./interfaces/IRegisterableAsset.sol";
import "./interfaces/IAssets.sol";
import "./Constants.sol";

import "hardhat/console.sol";

contract Assets is IAssets, ERC1155, Ownable, EIP712MetaTransaction {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.UintSet;

  uint8 constant internal _vers = 1;

  IAssets immutable public deprecatedAssets; 

  bytes32[] private _assetNames;
  uint256[] private _minIDs;

  // registry containing fungible / non-fungible tokens
  // fungible tokens have minID == totalSupply
  // nfts have a range of IDs, specified via totalSupply 
  struct AssetType {
    bool    isNFT;
    uint256 minID;
    uint256 totalSupply;
    uint256 currentSupply;
    mapping (address => bool) operators;
  }
  
  mapping(bytes32 => AssetType) private _assets;

  mapping (address => EnumerableSet.UintSet) private _accountTokens;

  constructor(address oldAssets) public ERC1155("/1155/{id}.json") EIP712MetaTransaction("Assets", "1")  {
    deprecatedAssets = IAssets(oldAssets);
  }

  function register(
    bytes32 name,
    bool    isNFT,
    uint256 totalSupply,
    address[] memory operators
  ) public onlyOwner {
    require(totalSupply > 0, "total supply must be greater than 0");

    uint256 minID;
    if (_assetNames.length == 0) {
      minID = 0;
    } else {
      require(_assets[name].totalSupply == 0, "asset name already taken");
      // get maxID of last asset, and add 1
      minID = _maxID(_assets[_assetNames[_assetNames.length - 1]]) + 1;
    }

    AssetType storage asset = _assets[name];
    asset.isNFT = isNFT;
    asset.minID = minID;
    asset.totalSupply = totalSupply;
    asset.currentSupply = 0;

    for (uint i = 0; i < operators.length; i++) {
      asset.operators[operators[i]] = true;
    }
    if (operators.length == 0) {
      asset.operators[msgSender()] = true;
    }

    require(_maxID(asset) < type(uint256).max, "out of ids");

    _assetNames.push(name);
    _minIDs.push(minID);
  }

  function registerAssetContract(
    address contractAddress
  ) public onlyOwner {
    IRegisterableAsset asset = IRegisterableAsset(contractAddress);
    register(
      asset.assetName(),
      asset.assetIsNFT(),
      asset.assetTotalSupply(),
      asset.assetOperators()
    );
  }

  function addOperator(address operator_, bytes32 name) external returns (bool) {
    AssetType storage asset = _assets[name];
    require(asset.operators[msgSender()], "Assets: Not authorized to add");
    asset.operators[operator_] = true;
    return true;
  }

  function removeOperator(address operator_, bytes32 name) external returns (bool) {
    AssetType storage asset = _assets[name];
    require(asset.operators[msgSender()], "Assets: Not authorized to add");
    delete asset.operators[operator_];
    return true;
  }

  function mint(
    address account,
    bytes32 name,
    uint256 amount,
    bytes memory data
  ) override external returns(uint256[] memory) {
    AssetType storage asset = _assets[name];
    require(asset.operators[msgSender()], "Assets: Not authorized to mint");
    require((asset.currentSupply + amount) <= asset.totalSupply, "Assets: Token supply exhausted");

    uint256[] memory mintedIDs;

    if (asset.isNFT) {
      mintedIDs = new uint256[](amount);
      for (uint i; i < amount; i++) {
        _mint(account, asset.minID + asset.currentSupply + i, 1, data);
        mintedIDs[i] = asset.minID + asset.currentSupply + i;
      }
    } else {
      mintedIDs = new uint256[](1);
      mintedIDs[0] = asset.minID;
      _mint(account, asset.minID, amount, data);
    }

    asset.currentSupply = asset.currentSupply + amount;
    return mintedIDs;
  }

  /**
  This function is for assets like equipment where it's kind of an NFT and kind of a fungible
  ie: it's an NFT (there's only 1 contract), but there can be more than one of a type
  something like "5 swords" but we don't want to deploy a new contract per Equipment 
  */
  function forge(
    address account,
    uint id,
    uint amount,
    bytes memory data
  ) override external returns (bool) {
    bytes32 name = nameForID(id);
    AssetType storage asset = _assets[name];
    require(asset.operators[msgSender()], "Assets: Not authorized to forge");
    _mint(account, id, amount, data);
    return true;
  }
  
  function burn(
    address account,
    bytes32 name,
    uint256 amount
  ) override external {
    AssetType storage asset = _assets[name];
    require(asset.isNFT == false, "cannot burn NFTs");
    require(
      isApprovedOrOwner(account, msgSender(), asset.minID),
      "Assets: caller is not owner nor approved"
    );
    _burn(account, asset.minID, amount);
    asset.currentSupply = asset.currentSupply - amount;
  }

  function isOwner(
    address account,
    uint256 id
  ) override public view returns (bool) {
    return balanceOf(account, id) > 0;
  }

  function isApprovedOrOwner(
    address account,
    address operator,
    uint256 id
  ) override public view returns (bool) {
    return isApprovedForAll(account, operator) || ( account == operator && isOwner(account, id) );
  }

  // given an ID inside a minted range, return the type name
  function nameForID(
    uint256 id
  ) override public view returns (bytes32) {
    uint256 lastIndex = _minIDs.length - 1;
    for (uint256 i = 0; i <= lastIndex; i++) {
      if (i == lastIndex) {
        AssetType storage lastAsset = _assets[_assetNames[i]];
        if (id <= _maxID(lastAsset)) {
          return _assetNames[i];
        }
      } else if(_minIDs[i] <= id && id < _minIDs[i + 1]) {
        return _assetNames[i];
      }
    }
  }

  function idRange(
    bytes32 name
  ) override public view returns (uint256, uint256) {
    AssetType storage asset = _assets[name];
    if (asset.isNFT) {
      return (asset.minID, asset.minID + asset.totalSupply - 1);
    }
    return (asset.minID, asset.minID);
  }

  // has the token of name been minted
  function exists(
    bytes32 name,
    uint256 id
  ) override public view returns (bool) {
    AssetType storage asset = _assets[name];
    if (!asset.isNFT) {
      return asset.minID == id && asset.currentSupply > 0;
    }
    return asset.minID <= id && id < (asset.minID + asset.currentSupply);
  }

  function totalSupply(
    bytes32 name
  ) override external view returns (uint256) {
    return _assets[name].totalSupply;
  }

  function currentSupply(
    bytes32 name
  ) override external view returns (uint256) {
    return _assets[name].currentSupply;
  }

  function accountTokens(
    address account
  ) override public view returns (uint256[] memory) {
    uint256 tokenCount = _accountTokens[account].length(); 
    uint256[] memory ids = new uint256[](tokenCount);
    for (uint256 i = 0; i < tokenCount; i++) {
      ids[i] = _accountTokens[account].at(i);
    }
    return ids;
  }

  function _msgSender() internal view override(Context,EIP712MetaTransaction) returns (address payable) {
    return EIP712MetaTransaction.msgSender();
  }

  function _maxID(
    AssetType storage asset
  ) internal view returns(uint256) {
    if (asset.isNFT == false) {
      return asset.minID;
    }
    return asset.minID + asset.totalSupply - 1;
  }

  function _beforeTokenTransfer(
    address,
    address from,
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory
  ) internal override {
    for (uint256 i = 0; i < ids.length; i++) {
      if (from != address(0) && (balanceOf(from, ids[i]) - amounts[i]) <= 0) {
        _accountTokens[from].remove(ids[i]);
      }
      if (to != address(0)) {
        _accountTokens[to].add(ids[i]);
      }
    }
  }

  function onERC1155Received(
    address,
    address from,
    uint256 id,
    uint256 value,
    bytes calldata
  ) external returns(bytes4) {
    require(msg.sender == address(deprecatedAssets), "Assets#onERC1155Received: invalid old asset address");
    (uint prestigeStart, uint prestigeEnd) = deprecatedAssets.idRange(Constants.PRESTIGE_ASSET_NAME);
    require(id >= prestigeStart && id <= prestigeEnd, "Assets#Only supports prestige migration");
    
    AssetType storage prestige = _assets[Constants.PRESTIGE_ASSET_NAME];

    _mint(from, prestige.minID, value, '');
    
    return IERC1155Receiver.onERC1155Received.selector;
  }
}
