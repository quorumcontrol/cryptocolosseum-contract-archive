// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "./Constants.sol";
import "./interfaces/IDiceRolls.sol";

import "hardhat/console.sol";

contract DiceRoller is
    IDiceRolls,
    Ownable
{
    using SafeMath for uint256;

    uint256 public override latest;

    mapping(uint256 => RollParams) public rolls;

    function roll(uint256 random, PerformancePair[] calldata performance)
        public
        override
        onlyOwner
    {
        // console.log("---- dice roll");
        RollParams storage roll = rolls[latest + 1];
        roll.random = uint256(
            keccak256(abi.encodePacked(random, blockhash(block.number - 1)))
        );
        // console.log('pushing performances');
        for (uint256 i; i < performance.length; i++) {
            roll.performances.push(performance[i]);
        }
        roll.id = latest + 1;
        roll.blockNumber = block.number;
        latest++;
        emit DiceRoll(latest, roll.random);
    }

    function getLatestRoll() public view override returns (RollParams memory) {
        return getRoll(latest);
    }

    function getRoll(uint256 index)
        public
        view
        override
        returns (RollParams memory)
    {
        return rolls[index];
    }

    function getRange(uint256 start, uint256 last)
        public
        view
        override
        returns (RollParams[] memory)
    {
        // console.log("getRange:", start, last, latest);
        RollParams[] memory rolls_ = new RollParams[](last - start + 1);
        uint256 returnedRollsIndex;
        for (uint256 i = start; i <= last; i++) {
            // console.log('getRange add', i, 'random', rolls[i].random);
            rolls_[returnedRollsIndex] = rolls[i];
            returnedRollsIndex++;
        }
        return rolls_;
    }
}
