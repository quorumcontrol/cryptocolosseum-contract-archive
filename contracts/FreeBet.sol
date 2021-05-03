// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/access/Ownable.sol";

contract FreeBet is Ownable {
    mapping(address => uint32) public maxFreeBets;
    mapping(address => uint32) public usedFreeBets;

    function inc(address userAddress) public onlyOwner returns (uint32) {
        return usedFreeBets[userAddress]++;
    }

    function setMaxFreeBets(address userAddress, uint32 max) public onlyOwner {
        maxFreeBets[userAddress] = max;
    }
}
