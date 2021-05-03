// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "./meta/EIP712MetaTransaction.sol";
import "./Assets.sol";
import "./TournamentV4.sol";
import "./Constants.sol";

import "hardhat/console.sol";

// only calling this with the 5 because otherwise there's a build error conflicting with BettingPoolV4
interface IFaction5 {
    function byName(string calldata name) external returns (uint);
}

contract BettingPoolV5 is ERC1155Receiver, Ownable, EIP712MetaTransaction {
  using SafeMath for uint256;

  event BetPlaced(address indexed better, uint indexed tournamentId, uint indexed gladiatorId);

  uint256 constant private oneHundredPercent = 10**10;

  Assets immutable private _assets; // ERC-1155 Assets contract
  TournamentV4 immutable private _tournaments; // ERC-1155 Assets contract
  IFaction5 immutable private _faction;
  address immutable private _gladiatorContract;

  uint immutable private _prestigeId;

  uint8 public multiplier;
  uint8 public gladiatorPercent;

  mapping(uint256 => mapping(address => mapping(uint => uint))) public betsByUser;  //tournamentID => user => gladiator => amount
  mapping(uint256 => mapping(address => uint8)) public betCountByUser; // tournamentID => user => count; // only allow 2 bets per user
  mapping(uint256 => mapping(uint => uint)) public betsByGladiator; // tournamentID => gladiatorId => totalAmount
  mapping(uint256 => uint) public betsByTournament; // tournamentID => totalAmount

  mapping(uint256 => uint256) public incentivesByTournament; // tournamentID => amount of incentive

  mapping(uint256 => bool) private _claimedByGladiator; // tournamentID => true/false if already claimed by gladiator

  constructor(
    address _assetsAddress,
    address _tournamentAddress,
    address _gladiatorAddress,
    address _factionAddress
  ) EIP712MetaTransaction("BettingPool", "2") {
    require(
      _assetsAddress != address(0),
      "BettingPool#constructor: INVALID_INPUT _assetsAddress is 0"
    );
    Assets assetContract = Assets(_assetsAddress);
    _assets = assetContract;
    _tournaments = TournamentV4(_tournamentAddress);
    (uint start,) = assetContract.idRange(Constants.prestigeAssetName());
    _prestigeId = start;
    gladiatorPercent = 20;
    _gladiatorContract = _gladiatorAddress;
    _faction = IFaction5(_factionAddress);
  }

  function setIncentive(uint256 tournamentId, uint256 amount) external onlyOwner {
    incentivesByTournament[tournamentId] = amount;
  }

  function setGladiatorPercent(uint8 percent) external onlyOwner {
    gladiatorPercent = percent;
  }

  function expectedWinnings(uint tournamentId, address user, uint champion) public view returns (uint) {
    uint bet = betsByUser[tournamentId][user][champion];
    if (bet == 0) {
      return 0;
    }

    // calculate their percentage of all the *winners* of the tournament (those that picked the right gladiator)
    // percent calculated as 10 digits (10^10 is 100%);
    uint percentOfPool = (bet * oneHundredPercent).div(betsByGladiator[tournamentId][champion]);
    
    return betsByTournament[tournamentId].sub(gladiatorWinnings(tournamentId)).add(incentivesByTournament[tournamentId]).mul(percentOfPool).div(oneHundredPercent);
  }

  function withdraw(uint tournamentId) external returns (bool) {
    TournamentV4.Champion memory winner = _tournaments.getChampion(tournamentId);
    uint champion = winner.gladiator;

    address user = msgSender();

    uint winnings = expectedWinnings(tournamentId, user, champion);
    require(winnings > 0, "BettingPool#You didn't win");
    
    delete betsByUser[tournamentId][user][champion];
    delete betCountByUser[tournamentId][user];
    _assets.safeTransferFrom(address(this), user, _prestigeId, winnings, '');
    return true;
  }

  function gladiatorWinnings(uint tournamentId) internal view returns (uint) {
    return betsByTournament[tournamentId].mul(gladiatorPercent).div(100);
  }

  function claimForGladiator(uint tournamentId) external returns (bool) {
    require(!_claimedByGladiator[tournamentId], "Gladiators winnings already claimed");
    TournamentV4.Champion memory winner = _tournaments.getChampion(tournamentId);

    string memory factionName = _tournaments.factions(tournamentId)[winner.faction];
    uint factionID = _faction.byName(factionName);
    
    uint winnings = gladiatorWinnings(tournamentId);

    if (factionID > 0) {
      uint factionWinnings = winnings.mul(25).div(100);
      _assets.safeTransferFrom(address(this), address(_faction), _prestigeId, winnings, abi.encode(factionID));
      winnings = winnings.sub(factionWinnings);
    }

    // console.log('winnings', winnings);
    _claimedByGladiator[tournamentId] = true;
    _assets.safeTransferFrom(address(this), _gladiatorContract, _prestigeId, winnings, abi.encode(winner.gladiator));
    return true;
  }

  function migrate(address payable newAddress) external onlyOwner {
    // move all ptg to the new address and destroy this contract
    uint balance = _assets.balanceOf(address(this), _prestigeId);
    _assets.safeTransferFrom(address(this), newAddress, _prestigeId, balance, '');
    selfdestruct(newAddress);
  }

  function onERC1155Received(
    address, // operator
    address from,
    uint256 id,
    uint256 value,
    bytes calldata data
  ) external override returns(bytes4) {
    require(msg.sender == address(_assets), "BettingPool#onERC1155Received: invalid asset address");
    require(id == _prestigeId, "BettingPool#Invalid token send");
    if (from == address(0)) {
      // this is a MINT so just accept it
      return IERC1155Receiver.onERC1155Received.selector;
    }
    (uint256 tournamentId, uint256 gladiatorId) = abi.decode(data, (uint256, uint256));
    // console.log("bet!", tournamentId, gladiatorId, from);
    require(!_tournaments.started(tournamentId), "BettingPool#Tournament already started");

    // if this is a *new* bet on the tournament then increase the count
    // but allow unlimited increases in your betting;
    if (betsByUser[tournamentId][from][gladiatorId] == 0) {
      require(betCountByUser[tournamentId][from] < 2, "BettingPool#Too many bets");
      betCountByUser[tournamentId][from] += 1; 
    }
    betsByUser[tournamentId][from][gladiatorId] += value;
    betsByGladiator[tournamentId][gladiatorId] += value;
    betsByTournament[tournamentId] += value;
    
    emit BetPlaced(from, tournamentId, gladiatorId);

    return IERC1155Receiver.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] memory,
    uint256[] memory,
    bytes calldata
  ) pure public override returns(bytes4) {
      revert("BettingPool#No batch allowed");
  }

  function _msgSender() internal view override(Context,EIP712MetaTransaction) returns (address payable) {
    return EIP712MetaTransaction.msgSender();
  }
}
