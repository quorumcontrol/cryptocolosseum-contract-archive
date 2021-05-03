pragma solidity ^0.7.4;

import "./AssetsERC20Wrapper.sol";
import "./CloneFactory.sol";

contract WrapperFactory is CloneFactory {

  address public libraryAddress;
  address public holderAddress;

  mapping(uint256 => address) public getWrapper; // mapping of tokenID to address

  event WrapperCreated(address proxyAddress);

  constructor(address _libraryAddress, address _holderAddress) {
    libraryAddress = _libraryAddress;
    holderAddress = _holderAddress;
  }

  function createWrapper(uint256 tokenID, string calldata name, string calldata symbol) public returns(address) {
    require(getWrapper[tokenID] == address(0), "wrapper already created");
    address clone = createClone(libraryAddress);
    AssetsERC20Wrapper(clone).init(tokenID, name, symbol);
    getWrapper[tokenID] = address(clone);
    emit WrapperCreated(clone);
    return clone;
  }
}