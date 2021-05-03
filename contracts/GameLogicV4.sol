// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "hardhat/console.sol";
import "./interfaces/IGameLogicV4.sol";
import "./interfaces/IDiceRolls.sol";
import "./interfaces/ITournamentV4.sol";
import "./Gladiator.sol";
import "./Equipper.sol";
import "./interfaces/IGameEquipment.sol";

contract GameLogicV4 is IGameLogicV4 {
    using SafeMath for uint256;

    bytes32 constant HIT_POINTS = "hitpoints";
    bytes32 constant ATTACK = "attack";
    bytes32 constant DEFENSE = "defense";
    bytes32 constant NAME = "name";

    uint256 constant MAX_PERCENTAGE = 10**6;

    Gladiator immutable private _gladiators;
    ITournamentV4 immutable private _tournament;
    Equipper immutable public equipper;

    constructor(
        address gladiatorContract, 
        address tournamentContract, 
        address assetsContract,
        address equipmentContract
    ) {
        _gladiators = Gladiator(gladiatorContract);
        _tournament = ITournamentV4(tournamentContract);
        equipper = new Equipper(equipmentContract, tournamentContract, assetsContract);
    } 

    struct Narrative {
        bool attackerIsWinner;
        uint256 attacker;
        uint256 defender;
        int256 attackRoll;
        int256 defenseRoll;
        int256 attackFactionBonus;
        int256 defenseFactionBonus;
        uint256[] attackEquipment;
        uint256[] defenseEquipment;
        int256 attackerHP;
        int256 defenderHP;
    }

    struct Bonus {
        uint256 id;
        int256 hitPoints;
        int256 attack;
        int256 defense;
    }

    struct OriginalStats {
        uint id;
        int256 hitPoints;
        uint attack;
        uint defense;
    }

    // expected is the uint[] from RollParams#performance
    function getFactionBonuses(
        IDiceRolls.PerformancePair[] memory previous,
        IDiceRolls.PerformancePair[] memory current
    ) internal pure returns (uint256[] memory bonuses) {
        bonuses = new uint256[](current.length);
        for (uint256 i; i < current.length; i++) {
            int256 prev = int256(previous[i].value);
            if (prev == 0) {
                prev = int256(current[i].value);
            }
            // if previous is still 0 then we don't
            // want to divide by zero, so continue
            if (prev == 0) {
                continue;
            }
            int256 bonus = (prev - (int256(current[i].value) * 100)) / prev;
            if (bonus < 0) {
                bonus = 0;
            }
            bonuses[i] = uint256(bonus);
        }
        return bonuses;
    }

    function factionBonus(
        ITournamentV4.Game memory game,
        uint256[] memory bonuses,
        ITournamentV4.GameGladiator memory gladiator
    ) internal view returns (Bonus memory bonus) {
        // console.log("faction: ", gladiator.faction);
        // console.log("bonus length: ", bonuses.length);
        int256 facBonus_ = int256(bonuses[gladiator.faction]);
        bonus.attack = facBonus_;
        bonus.defense = facBonus_;
    }

    function copyUses(uint256[] memory uses)
        internal
        pure
        returns (uint256[] memory newUses)
    {
        newUses = new uint256[](uses.length);
        for (uint256 i; i < uses.length; i++) {
            newUses[i] = uses[i];
        }
        return newUses;
    }

    function equipmentBonuses(
        ITournamentV4.GameGladiator memory gladiator,
        uint256 random,
        bool isAttacker
    ) internal view returns (Bonus memory bonus) {
        // turn to view from pure if turning on console.log
        for (uint256 i; i < gladiator.equipment.length; i++) {
            // console.logBool(isAttacker);
            // console.log('scanning equipment: ', i);
            IGameEquipment.EquipmentMetadata memory equipment =
                gladiator.equipment[i];
            // if it's already been used, then just continue
            if (
                equipment.numberOfUsesPerGame > 0 &&
                gladiator.equipmentUses[i] >= equipment.numberOfUsesPerGame
            ) {
                continue;
            }
            // if this is the attacker, but this equipment does nothing for them
            // then just continue
            if (
                isAttacker && equipment.hitPoints == 0 && equipment.attack == 0
            ) {
                continue;
            }
            // if this is not the attacker, but the equipent only affects attack then
            // don't use it.
            if (
                !isAttacker &&
                equipment.hitPoints == 0 &&
                equipment.defense == 0
            ) {
                continue;
            }
            // otherwise roll the dice to see if it'll be used
            bool useEquipment = true;
            
            // 0 means 100% of the time anything more is a percentage that we roll for;
            if (equipment.percentChanceOfUse > 0) {
                uint256 equipRoll =
                    uint256(keccak256(abi.encodePacked(random, equipment.id)));
                useEquipment = equipRoll.mod(MAX_PERCENTAGE) <=
                    equipment.percentChanceOfUse;
            }

            if (useEquipment) {
                // we'll go ahead and use this one
                // console.log('increasing usage', equipment.name, ' from ', gladiator.equipmentUses[i]);
                gladiator.equipmentUses[i]++;

                bonus.hitPoints += equipment.hitPoints;
                bonus.attack += equipment.attack;
                bonus.defense += equipment.defense;
            }
        }
        return bonus;
    }

    function concatBonuses(Bonus[] memory bonuses)
        internal
        pure
        returns (Bonus memory bonus)
    {
        for (uint256 i; i < bonuses.length; i++) {
            bonus.hitPoints += bonuses[i].hitPoints;
            bonus.attack += bonuses[i].attack;
            bonus.defense += bonuses[i].defense;
        }
        return bonus;
    }

    function getBonuses(
        ITournamentV4.Game memory game,
        uint256 random,
        uint256[] memory factionBonuses,
        ITournamentV4.GameGladiator memory gladiator,
        bool isAttacker
    ) internal view returns (Bonus memory bonus) {
        Bonus[] memory bonuses = new Bonus[](2);
        bonuses[0] = factionBonus(game, factionBonuses, gladiator);
        bonuses[1] = equipmentBonuses(gladiator, random, isAttacker);
        return concatBonuses(bonuses);
    }

    function getRoll(
        ITournamentV4.Game memory game,
        IDiceRolls.RollParams memory roll,
        uint256[] memory factionBonuses,
        uint256 lastWinner
    ) public view returns (RollReturn memory) {
        // console.log('bonus length', bonuses.lenth, 'random: ', roll.random );
        uint256 random = roll.random;
        // console.log("random: (gameid, random) ", game.id, random);

        // first we roll a d3
        // 0 means player 1 is attacker
        // 1 means player 2 is attacker
        // 2 means last player to win is attacker
        uint256 d3 = random.mod(3);
        uint256 attacker = d3;
        if (attacker == 2) {
            attacker = lastWinner;
        }
        // console.log('attacker', attacker);
        uint256 defender = (attacker + 1).mod(game.players.length);

        ITournamentV4.GameGladiator memory attackGladiator =
            game.players[attacker];
        ITournamentV4.GameGladiator memory defendGladiator =
            game.players[defender];

        // console.log("attack/defense gladiator: ", attackGladiator.id, defendGladiator.id);

        uint256 attackRandom =
            uint256(keccak256(abi.encodePacked(attackGladiator.id, random)));
        uint256 defenseRandom =
            uint256(keccak256(abi.encodePacked(defendGladiator.id, random)));

        // console.log('attack/defense random', random, attackRandom, defenseRandom);

        Bonus memory attackBonus =
            getBonuses(
                game,
                attackRandom,
                factionBonuses,
                attackGladiator,
                true
            );
        Bonus memory defenseBonus =
            getBonuses(
                game,
                defenseRandom,
                factionBonuses,
                defendGladiator,
                false
            );

        // console.log('attackGladiator: ', attackGladiator.faction, 'bonus', bonuses[0]);
        // console.log("bonus: (attack,defend): ", bonuses[game.factions[attacker]], bonuses[game.factions[defender]]);
        int256 attackRoll = int256(attackRandom.mod(attackGladiator.attack));
        int256 defenseRoll = int256(defenseRandom.mod(defendGladiator.defense));

        attackRoll += attackBonus.attack;
        defenseRoll += defenseBonus.defense;

        return
            RollReturn({
                attacker: attacker,
                defender: defender,
                attackRoll: attackRoll,
                defenseRoll: defenseRoll,
                attackHpAddition: attackBonus.hitPoints,
                defenseHpAddition: defenseBonus.hitPoints
            });
    }

    // TODO: this is a hacky repeat of roll below, but for now it suffices
    function blowByBlow(
        ITournamentV4.Game memory game,
        IDiceRolls.RollParams[] memory rolls
    ) public view returns (Narrative[] memory narratives) {
        narratives = new Narrative[](rolls.length);
        // console.log("blow by blow: ", game.id, rolls.length);
        uint256 lastWinner = 0;
        IDiceRolls.RollParams memory previousRoll;

        // set it up as 0
        uint256[] memory factionBonuses =
            new uint256[](rolls[0].performances.length);

        for (uint256 i = 0; i < rolls.length; i++) {
            Narrative memory narrative = narratives[i];

            IDiceRolls.RollParams memory roll = rolls[i];
            if (i > 0) {
                factionBonuses = getFactionBonuses(
                    rolls[i - 1].performances,
                    roll.performances
                );
            }

            RollReturn memory rollResult =
                getRoll(game, roll, factionBonuses, lastWinner);

            int256 attackRoll = rollResult.attackRoll;
            int256 defenseRoll = rollResult.defenseRoll;
            uint256 attacker = rollResult.attacker;
            uint256 defender = rollResult.defender;

            narrative.attacker = game.players[attacker].id;
            narrative.defender = game.players[defender].id;
            narrative.attackRoll = attackRoll;
            narrative.defenseRoll = defenseRoll;

            narrative.attackFactionBonus = int256(
                factionBonuses[game.players[attacker].faction]
            );
            narrative.defenseFactionBonus = int256(
                factionBonuses[game.players[defender].faction]
            );

            narrative.attackEquipment = copyUses(
                game.players[attacker].equipmentUses
            );
            narrative.defenseEquipment = copyUses(
                game.players[defender].equipmentUses
            );

            game.players[attacker].hitPoints += rollResult.attackHpAddition;
            game.players[defender].hitPoints += rollResult.defenseHpAddition;

            narrative.attackerHP = game.players[attacker].hitPoints;
            if (attackRoll > defenseRoll) {
                // attack was successful!
                // console.log("successful attack: ");
                // console.logInt(attackRoll - defenseRoll);
                // console.logInt(game.players[defender].hitPoints);
                game.players[defender].hitPoints -= (attackRoll - defenseRoll);
                narrative.defenderHP = game.players[defender].hitPoints;
                // console.log('setting hp to');
                // console.logInt(narrative.defenderHP);
                if (game.players[defender].hitPoints <= 0) {
                    // console.log("death blow after # of rolls: ", i);
                    game.decided = true;
                    game.winner = uint8(attacker);
                    game.lastRoll = roll.id;

                    narrative.attackerIsWinner = true;
                    break;
                }
                lastWinner = attacker;
            } else {
                narrative.defenderHP = game.players[defender].hitPoints;
                lastWinner = defender;
                // console.log("defense win");
            }
        }
        return narratives;
    }

    function roll(
        ITournamentV4.Game memory game,
        IDiceRolls.RollParams[] memory rolls // use view if you enable console.log
    ) public view override returns (ITournamentV4.Game memory) {
        // console.log("roll: ", game.id, rolls.length);
        uint256 lastWinner = 0;
        IDiceRolls.RollParams memory previousRoll;

        // set it up as 0
        uint256[] memory factionBonuses =
            new uint256[](rolls[0].performances.length);

        (uint256 start, bool found) = indexOf(rolls, game.firstRoll);
        // require(found, "no first roll found in rolls");
        if (!found) {
            return game;
        }

        for (uint256 i = start; i < rolls.length; i++) {
            IDiceRolls.RollParams memory roll = rolls[i];
            if (i > 0) {
                factionBonuses = getFactionBonuses(
                    rolls[i - 1].performances,
                    roll.performances
                );
            }

            RollReturn memory rollResult =
                getRoll(game, roll, factionBonuses, lastWinner);

            int256 attackRoll = rollResult.attackRoll;
            int256 defenseRoll = rollResult.defenseRoll;

            game.players[rollResult.attacker].hitPoints += rollResult
                .attackHpAddition;
            game.players[rollResult.defender].hitPoints += rollResult
                .defenseHpAddition;

            if (attackRoll > defenseRoll) {
                // attack was successful!
                // console.log("successful attack: ", attackRoll.sub(defenseRoll));
                game.players[rollResult.defender].hitPoints -= (attackRoll -
                    defenseRoll);
                if (game.players[rollResult.defender].hitPoints <= 0) {
                    // console.log("death blow after # of rolls: ", i);
                    game.decided = true;
                    game.winner = uint8(rollResult.attacker);
                    game.lastRoll = roll.id;
                    break;
                }
                lastWinner = rollResult.attacker;
            } else {
                lastWinner = rollResult.defender;
                // console.log("defense win");
            }
        }
        return game;
    }

    // TODO: binary search
    function indexOf(IDiceRolls.RollParams[] memory rolls, uint256 id)
        internal
        view
        returns (uint256 idx, bool found)
    {
        for (idx = 0; idx < rolls.length; idx++) {
            if (rolls[idx].id == id) {
                return (idx, true);
            }
        }
        return (0, false);
    }

    function _getRound(
        ITournamentV4.GameGladiator[] memory roundPlayers,
        IDiceRolls.RollParams[] memory rolls,
        uint256 firstRollIndex
    ) internal view returns (ITournamentV4.Round memory round) {
        round.games = new ITournamentV4.Game[](roundPlayers.length.div(2));
        // console.log("fetching: ", firstRollIndex);
        if (firstRollIndex >= rolls.length) {
            uint256 gameId = 0;
            for (uint256 i; i < roundPlayers.length; i += 2) {
                ITournamentV4.Game memory game;

                ITournamentV4.GameGladiator[] memory players =
                    new ITournamentV4.GameGladiator[](2);
                players[0] = roundPlayers[i];
                players[1] = roundPlayers[i + 1];

                game.players = players;
                game.id = gameId;
                round.games[gameId] = game;
                gameId++;
            }
            return round;
        }
        uint256 firstRoll = rolls[firstRollIndex].id;
        round.firstRoll = firstRoll;

        bool lastGameIsFinished = true;

        uint256 gameId = 0;
        for (uint256 i; i < roundPlayers.length; i += 2) {
            ITournamentV4.Game memory game;

            ITournamentV4.GameGladiator[] memory players =
                new ITournamentV4.GameGladiator[](2);
            players[0] = roundPlayers[i];
            players[1] = roundPlayers[i + 1];
            // console.log("player 0: ", players[0].id);
            // console.log("player 1: ", players[1].id);

            game.players = players;
            game.id = gameId;
            if (lastGameIsFinished) {
                game.firstRoll = firstRoll;
                // console.log("calculatin game", i, game.id, firstRoll);
                // console.log(game.players.length);
                // only calculate if the last game was finished
                game = roll(game, rolls);
            }
            if (game.decided) {
                // console.log("setting firstRoll: ", game.lastRoll);
                firstRoll = game.lastRoll + 1;
                lastGameIsFinished = true;
            } else {
                lastGameIsFinished = false;
            }
            round.games[gameId] = game;
            gameId++;
        }
        if (lastGameIsFinished) {
            round.lastRoll = firstRoll - 1; // firstRoll has been updating
        }
        return round;
    }

     // TODO: binary search
    function indexOfGladiator(OriginalStats[] memory originalStats, uint256 id)
        internal
        pure
        returns (uint256 idx)
    {
        for (idx = 0; idx < originalStats.length; idx++) {
            if (originalStats[idx].id == id) {
                return idx;
            }
        }
        require(false, "should not get here");
        return 0;
    }

    function restoreGladiator(
        ITournamentV4.GameGladiator memory gladiator,
        OriginalStats[] memory originalStats
    ) internal pure returns (ITournamentV4.GameGladiator memory) {
        uint idx = indexOfGladiator(originalStats, gladiator.id);
        OriginalStats memory stats = originalStats[idx];
        gladiator.hitPoints = stats.hitPoints;
        gladiator.attack = stats.attack;
        gladiator.defense = stats.defense;
        gladiator.equipmentUses = new uint[](gladiator.equipmentUses.length);
        return gladiator;
    }

    function getWinners(
        ITournamentV4.Round memory round,
        OriginalStats[] memory originalStats
    )
        internal
        pure
        returns (ITournamentV4.GameGladiator[] memory players)
    {
        players = new ITournamentV4.GameGladiator[](round.games.length);
        for (uint256 i; i < round.games.length; i++) {
            ITournamentV4.Game memory game = round.games[i];
            require(game.decided, "Winners not decided");
            players[i] = restoreGladiator(game.players[game.winner], originalStats);
        }
        return players;
    }

    function tournamentWinner(
        uint tournamentId
    ) public view override returns (uint256 registrationId, uint256 lastRoll) {
        ITournamentV4.Round[] memory rounds = bracket(tournamentId, -1);
        ITournamentV4.Round memory round = rounds[rounds.length - 1];
        ITournamentV4.Game memory game = round.games[0];
        require(game.decided, "Tournament Not Decided");
        return (game.players[game.winner].registrationId, game.lastRoll);
    }

    function tournament(
        ITournamentV4.GameGladiator[] memory gladiators,
        IDiceRolls.RollParams[] memory rolls
    ) public view override returns (ITournamentV4.Round[] memory rounds) {
        ITournamentV4.Round memory currentRound;
        rounds = new ITournamentV4.Round[](log2(gladiators.length)); // TODO: check this math
        
        OriginalStats[] memory originalStats = new OriginalStats[](gladiators.length);
        for (uint i = 0; i < gladiators.length; i++) {
            originalStats[i] = OriginalStats({
                id: gladiators[i].id,
                hitPoints: gladiators[i].hitPoints,
                attack: gladiators[i].attack,
                defense: gladiators[i].defense
            });
        }

        for (uint256 i = 0; i < rounds.length; i++) {
            if (i == 0) {
                // console.log("round 0");
                currentRound = _getRound(gladiators, rolls, 0);
            } else {
                // console.log("round ", i);
                (uint256 start, bool found) =
                    indexOf(rolls, currentRound.lastRoll);
                require(found, "no roll found");
                currentRound = _getRound(
                    getWinners(currentRound, originalStats),
                    rolls,
                    start + 1
                );
            }
            rounds[i] = currentRound;
            if (!currentRound.games[currentRound.games.length - 1].decided) {
                break;
            }
        }

        return rounds;
    }

    function bracket(uint tournamentId, int specifiedLastRoll) public view override returns (ITournamentV4.Round[] memory rounds) {
        ITournamentV4.GameGladiator[] memory gladiators = gameGladiators(tournamentId);
        // if tournament hasn't started yet
        if (!_tournament.started(tournamentId)) {
            IDiceRolls.RollParams[] memory rolls;
            return tournament(gladiators, rolls);
        }

        IDiceRolls roller = _tournament.roller(tournamentId);
        uint firstRoll = _tournament.firstRoll(tournamentId);
        
        uint lastRoll;

        // user sends in -1 to mean "the whole tournament
        if (specifiedLastRoll < 0) {
            lastRoll = _tournament.lastRoll(tournamentId);
            if (lastRoll == 0) {
                lastRoll = roller.latest();
            }
        } else {
            lastRoll = uint(specifiedLastRoll);
        }
        
        return tournament(gladiators, roller.getRange(firstRoll, lastRoll));
    }


    // Gladiator stuff

    function getGladiator(
        uint256 registrationId,
        uint256 tournamentId,
        ITournamentV4.Registration memory reg
    ) internal view returns (ITournamentV4.GameGladiator memory gladiator) {
        uint256 id = reg.gladiator;
        gladiator.id = id;
        gladiator.faction = reg.faction;
        gladiator.registrationId = registrationId;
        gladiator.name = _gladiators.name(id);
        gladiator.hitPoints = int256(_gladiators.getProperty(id, HIT_POINTS));
        gladiator.attack = uint256(_gladiators.getProperty(id, ATTACK));
        gladiator.defense = uint256(_gladiators.getProperty(id, DEFENSE));
        gladiator.equipment = equipper.gladiatorEquipment(tournamentId, id);
        gladiator.equipmentUses = new uint256[](gladiator.equipment.length);
        return gladiator;
    }

    function gameGladiators(uint256 tournamentId)
        public
        view
        returns (ITournamentV4.GameGladiator[] memory gladiators)
    {
        ITournamentV4.Registration[] memory registrations = _tournament.registrations(tournamentId);
        return _gameGladiators(tournamentId, registrations);
    }

    function _gameGladiators(
        uint256 tournamentId,
        ITournamentV4.Registration[] memory registrations
    ) internal view returns (ITournamentV4.GameGladiator[] memory gladiators) {
        gladiators = new ITournamentV4.GameGladiator[](registrations.length);
        for (uint256 i; i < registrations.length; i++) {
            gladiators[i] = getGladiator(i, tournamentId, registrations[i]);
        }
        return gladiators;
    }
    
 // see: https://ethereum.stackexchange.com/questions/8086/logarithm-math-operation-in-solidity
    function log2(uint256 x) internal pure returns (uint256 y) {
        assembly {
            let arg := x
            x := sub(x, 1)
            x := or(x, div(x, 0x02))
            x := or(x, div(x, 0x04))
            x := or(x, div(x, 0x10))
            x := or(x, div(x, 0x100))
            x := or(x, div(x, 0x10000))
            x := or(x, div(x, 0x100000000))
            x := or(x, div(x, 0x10000000000000000))
            x := or(x, div(x, 0x100000000000000000000000000000000))
            x := add(x, 1)
            let m := mload(0x40)
            mstore(
                m,
                0xf8f9cbfae6cc78fbefe7cdc3a1793dfcf4f0e8bbd8cec470b6a28a7a5a3e1efd
            )
            mstore(
                add(m, 0x20),
                0xf5ecf1b3e9debc68e1d9cfabc5997135bfb7a7a3938b7b606b5b4b3f2f1f0ffe
            )
            mstore(
                add(m, 0x40),
                0xf6e4ed9ff2d6b458eadcdf97bd91692de2d4da8fd2d0ac50c6ae9a8272523616
            )
            mstore(
                add(m, 0x60),
                0xc8c0b887b0a8a4489c948c7f847c6125746c645c544c444038302820181008ff
            )
            mstore(
                add(m, 0x80),
                0xf7cae577eec2a03cf3bad76fb589591debb2dd67e0aa9834bea6925f6a4a2e0e
            )
            mstore(
                add(m, 0xa0),
                0xe39ed557db96902cd38ed14fad815115c786af479b7e83247363534337271707
            )
            mstore(
                add(m, 0xc0),
                0xc976c13bb96e881cb166a933a55e490d9d56952b8d4e801485467d2362422606
            )
            mstore(
                add(m, 0xe0),
                0x753a6d1b65325d0c552a4d1345224105391a310b29122104190a110309020100
            )
            mstore(0x40, add(m, 0x100))
            let
                magic
            := 0x818283848586878898a8b8c8d8e8f929395969799a9b9d9e9faaeb6bedeeff
            let
                shift
            := 0x100000000000000000000000000000000000000000000000000000000000000
            let a := div(mul(x, magic), shift)
            y := div(mload(add(m, sub(255, a))), shift)
            y := add(
                y,
                mul(
                    256,
                    gt(
                        arg,
                        0x8000000000000000000000000000000000000000000000000000000000000000
                    )
                )
            )
        }
    }
}
