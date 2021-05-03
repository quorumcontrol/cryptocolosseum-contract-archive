// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

interface IDiceRolls {
    event DiceRoll(uint256 indexed id, uint256 random);

    struct RollParams {
        uint256 id;
        uint256 random;
        PerformancePair[] performances;
        uint256 blockNumber;
    }

    struct PerformancePair {
        bytes32 name;
        uint256 value;
    }

    function latest() external virtual view returns (uint);

    function roll(uint256 random, PerformancePair[] calldata performance)
        external
        virtual;

    function getLatestRoll() external view virtual returns (RollParams memory);

    function getRoll(uint256 index)
        external
        view
        virtual
        returns (RollParams memory);

    function getRange(uint256 start, uint length)
        external
        view
        virtual
        returns (RollParams[] memory);
}
