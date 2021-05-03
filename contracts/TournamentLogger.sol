// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TournamentLogger is Ownable {
    using EnumerableSet for EnumerableSet.UintSet;

    EnumerableSet.UintSet private tournaments;

    function add(uint tournamentId) public onlyOwner {
        tournaments.add(tournamentId);
    }

    function all() public view returns (uint[] memory ids) {
        uint len = tournaments.length();
        ids = new uint[](len);
        for (uint i; i < len; i++) {
            ids[i] = tournaments.at(i);
        }
        return ids;
    }

    function length() public view returns (uint) {
        return tournaments.length();
    }

    function slice(uint start, uint length) public view returns (uint[] memory ids) {
        ids = new uint[](length);
        uint idsIndx = 0;
        for (uint i = start; i < start + length; i++) {
            ids[idsIndx] = tournaments.at(i);
            idsIndx++;
        }
        return ids;
    }
    
}
