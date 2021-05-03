// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "./interfaces/ITournamentV4.sol";
import "./interfaces/IDiceRolls.sol";
import "./Assets.sol";
import "./interfaces/IGameEquipment.sol";

import "hardhat/console.sol";

contract Equipper is ERC1155Receiver {
    using SafeMath for uint256;

    IGameEquipment public immutable equipment;
    ITournamentV4 private immutable _tournament;
    Assets private immutable _assets; // ERC-1155 Assets contract

    constructor(
        address equipmentContract,
        address tournamentContractAddress,
        address assetsContract
    ) {
        equipment = IGameEquipment(equipmentContract);
        _tournament = ITournamentV4(tournamentContractAddress);
        _assets = Assets(assetsContract);
    }

    mapping(uint256 => mapping(uint256 => IGameEquipment.EquipmentMetadata[]))
        public equippings; // tournamentId => gladiatorId => array of equipment

    function gladiatorEquipment(uint256 tournamentId, uint256 gladiatorId)
        public
        view
        returns (IGameEquipment.EquipmentMetadata[] memory)
    {
        return equippings[tournamentId][gladiatorId];
    }

    function handleEquipment(
        address,
        uint256 id,
        uint256 value,
        bytes calldata data // abi encoded uint256,uint256 tournamentId, gladiatorId
    ) internal returns (bool) {
        // TODO: allow fungible equipment
        require(
            value == 1,
            "Equipper#onERC1155BatchReceived: may only add one equipment at a time"
        );

        (uint256 tournamentId, uint256 gladiatorId) =
            abi.decode(data, (uint256, uint256));

        require(
            !_tournament.started(tournamentId),
            "Equipper#No equippings after tournament start"
        );
        require(
            equippings[tournamentId][gladiatorId].length < 3,
            "Equipper#Only 3 Equippings per gladiator per tournament"
        );

        equippings[tournamentId][gladiatorId].push(equipment.getMetadata(id));
        return true;
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = id;
        values[0] = value;
        onERC1155BatchReceived(operator, from, ids, values, data);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, //operator
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes calldata data // abi.encoded (uint256 tournamentId, uint16 faction)
    ) public override returns (bytes4) {
        require(
            msg.sender == address(_assets),
            "Tournament#onERC1155BatchReceived: invalid asset address"
        );

        for (uint256 i = 0; i < ids.length; i++) {
            if (_assets.exists("equipment", ids[i])) {
                require(
                    handleEquipment(from, ids[i], values[i], data),
                    "error handling equipment"
                );
                continue; // stop processing hr
            }
            revert("Unknown token type");
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
}
