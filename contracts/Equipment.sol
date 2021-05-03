// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAssets.sol";
import "./interfaces/IRegisterableAsset.sol";
import "./EnumerableMap.sol";
import "./meta/EIP712MetaTransaction.sol";
import "./interfaces/IGameEquipment.sol";

import "hardhat/console.sol";

contract Equipment is Ownable, IRegisterableAsset, IGameEquipment, EIP712MetaTransaction {
    using SafeMath for uint256;
    using EnumerableMap for EnumerableMap.Map;

    bytes32 constant ASSET_NAME = "equipment";
    uint256 constant TOTAL_SUPPLY = 2**40;

    IAssets public immutable assets;

    mapping(uint256 => EquipmentMetadata) public metadata;

    constructor(address assetsAddress)
        public
        EIP712MetaTransaction("Equipment", "1")
    {
        assets = IAssets(assetsAddress);
    }

    function assetName() public view override returns (bytes32) {
        return ASSET_NAME;
    }

    function assetTotalSupply() public pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function assetIsNFT() public pure override returns (bool) {
        return true;
    }

    function assetOperators() public view override returns (address[] memory) {
        address[] memory operators = new address[](2);
        operators[0] = address(this);
        operators[1] = owner();
        return operators;
    }

    function idRange() public view returns (uint256, uint256) {
        return assets.idRange(ASSET_NAME);
    }

    function getMetadata(uint id) public override view returns (EquipmentMetadata memory equipment) {
        equipment = metadata[id];
        equipment.id = id;
        return equipment;
    }

    function mint(
        address account,
        string memory name,
        int256 hitPoints,
        int256 attack,
        int256 defense,
        uint256 percentChanceOfUse,
        uint256 numberOfUsesPerGame
    ) external onlyOwner returns (uint256) {
        uint256[] memory ids = assets.mint(account, ASSET_NAME, 1, "");
        uint256 id = ids[0];

        EquipmentMetadata storage metadata = metadata[id];
        metadata.name = name;
        metadata.hitPoints = hitPoints;
        metadata.attack = attack;
        metadata.defense = defense;
        metadata.percentChanceOfUse = percentChanceOfUse;
        metadata.numberOfUsesPerGame = numberOfUsesPerGame;
        metadata.createdAt = bytes32(block.timestamp);

        return id;
    }

    function exists(uint256 id) external view returns (bool) {
        return assets.exists(ASSET_NAME, id);
    }

    function _msgSender()
        internal
        view
        override(Context, EIP712MetaTransaction)
        returns (address payable)
    {
        return EIP712MetaTransaction.msgSender();
    }
}
