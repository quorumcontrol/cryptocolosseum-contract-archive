// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

interface IGameEquipment {
    struct EquipmentMetadata {
        uint256 id;
        string name;
        int256 hitPoints;
        int256 attack;
        int256 defense;
        uint256 percentChanceOfUse;
        uint256 numberOfUsesPerGame;
        bytes32 createdAt;
    }

    function getMetadata(uint id) external virtual returns (EquipmentMetadata memory);

    
}
