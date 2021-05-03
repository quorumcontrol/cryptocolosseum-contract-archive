// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "./ITournamentV4.sol";
import "./IDiceRolls.sol";

interface IGameLogicV4 {

    struct RollReturn {
        uint attacker;
        uint defender;
        int attackRoll;
        int defenseRoll;
        int attackHpAddition;
        int defenseHpAddition;
    }

    function roll(
        ITournamentV4.Game memory game,
        IDiceRolls.RollParams[] memory rolls
    ) external view virtual returns (ITournamentV4.Game memory);

    // This interface allows running a tournament without *creating* a tournament (just seeing results)
    // We *theorize* this is useful as a welcome experience.
    function tournament(
        ITournamentV4.GameGladiator[] memory gladiators,
        IDiceRolls.RollParams[] calldata rolls
    ) external view virtual returns (ITournamentV4.Round[] memory rounds);

    function bracket(
        uint tournamentId,
        int lastRoll
    ) external view virtual returns (ITournamentV4.Round[] memory rounds);

    function tournamentWinner(
        uint tournamentId
    ) external view virtual returns (uint256 registrationId, uint lastRoll);
}
