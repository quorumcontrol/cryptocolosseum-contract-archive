// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./Assets.sol";
import "./Trophy.sol";
import "./Gladiator.sol";
import "./interfaces/IRegisterableAsset.sol";
import "./Constants.sol";
import "./interfaces/IGameLogicV4.sol";
import "./interfaces/IDiceRolls.sol";
import "./interfaces/ITournamentV4.sol";

import "hardhat/console.sol";

contract TournamentV4 is
    ITournamentV4,
    Ownable,
    IRegisterableAsset
{
    using SafeMath for uint256;

    bytes32 constant ASSET_NAME = "TournamentV4";
    uint256 constant TOTAL_SUPPLY = 2**38;
    uint256 constant ASSET_DECIMALS = 10**18;

    bytes32 constant HIT_POINTS = "hitpoints";
    bytes32 constant ATTACK = "attack";
    bytes32 constant DEFENSE = "defense";
    bytes32 constant NAME = "name";

    mapping(uint256 => TournamentData) private _tournaments;

    Assets private immutable _assets; // ERC-1155 Assets contract
    Gladiator private immutable _gladiator; // gladiator transfers
    Trophy public immutable trophies; // trophies minting

    bytes32 private immutable _gladiatorAssetName; 

    modifier onlyApproved(uint256 tournamentId) {
        require(
            _assets.isApprovedOrOwner(_msgSender(), _msgSender(), tournamentId),
            "Tournament: not an owner of the tournament"
        );
        _;
    }

    constructor(address _assetsAddress, address _gladiatorAddress) {
        require(
            _assetsAddress != address(0),
            "Tournament#constructor: INVALID_INPUT _assetsAddress is 0"
        );
        _assets = Assets(_assetsAddress);
        _gladiator = Gladiator(_gladiatorAddress);
        trophies = new Trophy(_assetsAddress, bytes32("TrophyV4"));
        _gladiatorAssetName = Gladiator(_gladiatorAddress).assetName();
    }

    function assetName() public pure override returns (bytes32) {
        return ASSET_NAME;
    }

    function assetTotalSupply() public pure override returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function assetIsNFT() public pure override returns (bool) {
        return true;
    }

    function assetOperators() public view override returns (address[] memory) {
        address[] memory operators = new address[](1);
        operators[0] = address(this);
        return operators;
    }

    function idRange() public view returns (uint256, uint256) {
        return _assets.idRange(ASSET_NAME);
    }

    function newTournament(
        string memory name,
        address gameLogic_,
        address roller_,
        uint8 totalRounds,
        uint256 notBefore,
        string[] memory factions
    ) public onlyOwner returns (uint256) {
        require(
            factions.length <= 65536,
            "Tournament#newTournament: Can only have 65536 factions"
        );

        address creator = _msgSender();

        uint256[] memory ids = _assets.mint(creator, ASSET_NAME, 1, "");
        uint256 tournamentId = ids[0];

        TournamentData storage tournament = _tournaments[tournamentId];
        tournament.name = name;
        tournament.creator = creator;
        tournament.totalRounds = totalRounds;
        tournament.factions = factions;
        tournament.gameLogic = IGameLogicV4(gameLogic_);
        tournament.notBefore = notBefore;
        tournament.roller = IDiceRolls(roller_);
        emit NewTournament(creator, notBefore, tournamentId);
        return tournamentId;
    }

    function registerGladiator(TournamentData storage tournament, uint tournamentId, uint id, uint16 faction) internal {
        require(
            faction < tournament.factions.length,
            "Tournament#onERC1155BatchReceived: faction does not exist"
        );
        require(_assets.exists(_gladiatorAssetName, id), "Tournament#Not a gladiator");

        tournament.registrations.push(
            Registration({gladiator: id, faction: faction})
        );
        emit RegistrationEvent(
            tournamentId,
            id,
            faction,
            tournament.registrations.length - 1
        );
    }

    function registerGladiators(uint tournamentId, uint[] calldata ids, uint16[] calldata factions) onlyOwner public {
        TournamentData storage tournament = _tournaments[tournamentId];

        require(
            tournament.totalRounds > 0,
            "Tournament#onERC1155BatchReceived: tournament does not exist"
        );
        require(
            !started(tournamentId),
            "Tournament#onERC1155BatchReceived: tournament already started"
        );
        require(
            tournament.registrations.length + ids.length <= this.maxGladiators(tournamentId),
            "Tournament#onERC1155BatchReceived: registration closed"
        );

        for (uint i; i < ids.length; i++) {
            registerGladiator(tournament, tournamentId, ids[i], factions[i]);
        }
    }

    function name(uint256 tournamentId) external view returns (string memory) {
        return _tournaments[tournamentId].name;
    }

    function firstRoll(uint256 tournamentId)
        external
        view
        override
        returns (uint256)
    {
        return _tournaments[tournamentId].firstRoll;
    }

    function notBefore(uint256 tournamentId)
        external
        view
        override
        returns (uint256)
    {
        return _tournaments[tournamentId].notBefore;
    }

    function lastRoll(uint256 tournamentId)
        external
        view
        override
        returns (uint256)
    {
        return _tournaments[tournamentId].lastRoll;
    }

    function roller(uint256 tournamentId)
        external
        view
        override
        returns (IDiceRolls)
    {
        return _tournaments[tournamentId].roller;
    }

    function started(uint256 tournamentId) public override view returns (bool) {
        TournamentData storage tournament = _tournaments[tournamentId];
        // console.log('first role', tournament.firstRoll, 'latest', latest);
        uint256 _firstRoll = tournament.firstRoll;
        return _firstRoll > 0 && _firstRoll <= tournament.roller.latest();
    }

    function totalRounds(uint256 tournamentId) external view returns (uint256) {
        return _tournaments[tournamentId].totalRounds;
    }

    function maxGladiators(uint256 tournamentId)
        external
        view
        returns (uint256)
    {
        return 2**uint256(_tournaments[tournamentId].totalRounds);
    }

    function registrationCount(uint256 tournamentId)
        external
        view
        returns (uint256)
    {
        return _tournaments[tournamentId].registrations.length;
    }

    function registration(uint256 tournamentId, uint256 registrationId)
        external
        view
        returns (Registration memory)
    {
        return _tournaments[tournamentId].registrations[registrationId];
    }

    function registrations(uint256 tournamentId)
        external
        view
        override
        returns (Registration[] memory)
    {
        TournamentData storage tournament = _tournaments[tournamentId];
        return tournament.registrations;
    }

    function factions(uint256 tournamentId)
        external
        view
        returns (string[] memory)
    {
        TournamentData storage tournament = _tournaments[tournamentId];
        return tournament.factions;
    }

    function start(uint256 tournamentId) external {
        TournamentData storage tournament = _tournaments[tournamentId];
        require(
            block.timestamp > tournament.notBefore,
            "Tournament cannot start yet"
        );
        tournament.firstRoll = tournament.roller.latest().add(1);
    }

    function checkpoint(uint256 tournamentId) external {
        TournamentData storage tournament = _tournaments[tournamentId];

        (uint256 winner, uint256 tournamentLastRoll) =
            tournament.gameLogic.tournamentWinner(tournamentId);

        tournament.lastRoll = tournamentLastRoll;

        createTrophy(tournamentId, tournament, winner);
    }

    function createTrophy(
        uint256 tournamentId,
        TournamentData storage tournament,
        uint256 winnerId
    ) internal {
        Registration memory winner = tournament.registrations[winnerId];

        uint256 trophyId =
            trophies.mint(
                address(_gladiator),
                tournament.name,
                tournamentId,
                winner.gladiator
            );

        _assets.mint(
            address(_gladiator),
            Constants.prestigeAssetName(),
            10 * ASSET_DECIMALS,
            abi.encodePacked(winner.gladiator)
        );

        tournament.champion.faction = winner.faction;
        tournament.champion.gladiator = winner.gladiator;
        tournament.champion.trophy = trophyId;

        emit TournamentComplete(tournamentId, winner.gladiator);
    }

    function getChampion(uint256 tournamentId)
        public
        view
        returns (Champion memory)
    {
        TournamentData storage tournament = _tournaments[tournamentId];
        require(tournament.lastRoll > 0, "Tournament is still in progress");
        return tournament.champion;
    }
}
