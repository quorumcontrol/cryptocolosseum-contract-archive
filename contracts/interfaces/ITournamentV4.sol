// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "./IGameLogicV4.sol";
import "./IGameEquipment.sol";
import "./IDiceRolls.sol";

interface ITournamentV4 {
    event RegistrationEvent(
        uint256 indexed tournamentId,
        uint256 indexed gladiatorId,
        uint16 faction,
        uint256 registrationId
    );

    event NewTournament(address indexed creator, uint256 indexed notBefore, uint256 tournamentId);

    event TournamentComplete(uint256 indexed tournamentId, uint256 winner);

    struct Registration {
        uint16 faction;
        uint256 gladiator;
    }

    struct Champion {
        uint16 faction;
        uint256 gladiator;
        uint256 trophy;
    }

    struct TournamentData {
        string name;
        address creator;
        uint256 notBefore;
        uint256 firstRoll;
        uint256 lastRoll;
        IGameLogicV4 gameLogic;
        IDiceRolls roller;
        uint8 totalRounds;
        string[] factions;
        Champion champion;
        Registration[] registrations;
    }

    struct GameGladiator {
        string name;
        uint256 id;
        uint256 registrationId;
        int256 hitPoints;
        uint256 attack;
        uint256 defense;
        uint256 faction;
        IGameEquipment.EquipmentMetadata[] equipment;
        uint256[] equipmentUses;
    }

    struct Round {
        Game[] games;
        uint256 firstRoll;
        uint256 lastRoll;
    }

    struct Game {
        uint256 id;
        uint256 tournamentId;
        bool decided;
        uint8 winner;
        uint256 firstRoll;
        uint256 lastRoll;
        GameGladiator[] players;
    }

    function firstRoll(uint256 tournamentId) external view returns (uint256);

    function notBefore(uint256 tournamentId) external view returns (uint256);

    function started(uint256 tournamentId) external view returns (bool);

    function lastRoll(uint256 tournamentId) external view returns (uint256);

    function roller(uint256 tournamentId) external view returns (IDiceRolls);

    function registrations(uint256 tournamentId) external view returns (Registration[] memory);
}
