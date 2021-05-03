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

interface IFaction {
    function byName(string calldata name) external returns (uint);
}

contract BettingPoolV4 is ERC1155Receiver, Ownable, EIP712MetaTransaction {
  using SafeMath for uint256;

  event BetPlaced(address indexed better, uint indexed tournamentId, uint indexed gladiatorId);

  Assets immutable private _assets; // ERC-1155 Assets contract
  TournamentV4 immutable private _tournaments; // ERC-1155 Assets contract
  IFaction immutable private _faction;
  address immutable private _gladiatorContract;

  uint immutable private _prestigeId;

  uint8 public multiplier;
  uint8 public gladiatorPercent;

  mapping(uint256 => mapping(address => mapping(uint => uint))) public betsByUser;  //tournamentID => user => gladiator => amount
  mapping(uint256 => mapping(uint => uint)) public betsByGladiator; // tournamentID => gladiatorId => totalAmount
  mapping(uint256 => uint) public betsByTournament; // tournamentID => totalAmount

  mapping(uint256 => bool) private _claimedByGladiator; // tournamentID => true/false if already claimed by gladiator

  constructor(
    address _assetsAddress,
    address _tournamentAddress,
    address _gladiatorAddress,
    address _factionAddress
  ) public EIP712MetaTransaction("BettingPool", "1") {
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
    _faction = IFaction(_factionAddress);
  }

  function setMultiplier(uint8 multiplier_) external onlyOwner {
    multiplier = multiplier_;
  }

  function setGladiatorPercent(uint8 percent) external onlyOwner {
    gladiatorPercent = percent;
  }

  function expectedWinnings(uint tournamentId, address user, uint champion) public view returns (uint) {
    uint bet = betsByUser[tournamentId][user][champion];
    if (bet == 0) {
      return 0;
    }
    uint winningPool = betsByGladiator[tournamentId][champion];

    // percent calculated as 10 digits (10^10 is 100%);
    uint percentOfPool = (bet * 10**10).div(winningPool);
    
    uint winnings = betsByTournament[tournamentId].sub(gladiatorWinnings(tournamentId)).mul(percentOfPool).div(10**10);

    if (multiplier > 0) {
      // mint the multiplier for this winner
      winnings *= uint(multiplier);
    }
    return winnings;
  }

  function withdraw(uint tournamentId) external returns (bool) {
    TournamentV4.Champion memory winner = _tournaments.getChampion(tournamentId);
    uint champion = winner.gladiator;

    address user = msgSender();

    uint winnings = expectedWinnings(tournamentId, user, champion);
    require(winnings > 0, "BettingPool#You didn't win");
    
    delete betsByUser[tournamentId][user][champion];
    _assets.mint(address(this), Constants.prestigeAssetName(), winnings, '');
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
