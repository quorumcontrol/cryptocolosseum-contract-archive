// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IAssets.sol";
import "./meta/EIP712MetaTransaction.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";

import "hardhat/console.sol";

/**
This is a contract that sells Assets (equipment). Right now it just mints them without any care about the total supply.
Next feature after would be maintaining rarity.

You register an asset for sale, it will then mint and transfer an asset to the sender
 */
contract VendingMachine is Ownable, EIP712MetaTransaction, ERC1155Receiver {
    using SafeMath for uint256;

    uint256 private immutable _prestigeID; // id of the prestige token
    IAssets public immutable assets;

    event ItemForSale(uint256 indexed id, uint256 indexed price);
    event ItemRemoved(uint256 indexed id);

    mapping(uint256 => uint256) public itemsForSale; // mapping of assetId to price

    constructor(address assetsAddress, uint256 prestigeID)
        public
        EIP712MetaTransaction("VendingMachine", "1")
    {
        _prestigeID = prestigeID;
        assets = IAssets(assetsAddress);
    }

    function sellItem(uint id, uint price) external onlyOwner {
      itemsForSale[id] = price;
      emit ItemForSale(id, price);
    }

    function stopSellingItem(uint id) external onlyOwner {
      delete itemsForSale[id];
      emit ItemRemoved(id);
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data // abi.encoded (uint256 itemID)
    ) external override returns (bytes4) {
        require(
            msg.sender == address(assets),
            "VendingMachine#onERC1155BatchReceived: invalid asset address"
        );
        require(id == _prestigeID, "VendingMachine#OnlySupportsPrestige");
        uint256 itemId = abi.decode(data, (uint256));
        uint256 price = itemsForSale[itemId];
        require(price > 0, "VendingMachine#ItemNotForSale");
        require(value == price, "VendingMachine#NotEnoughPrestige");

        // if it is enough then mint it and send it
        require(assets.forge(from, itemId, 1, ""), "VendingMachine#ForgeFailed");

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes calldata data
    ) public override returns (bytes4) {
        revert("Batch not supported");
    }

    function _msgSender()
        internal
        view
        override(Context, EIP712MetaTransaction)
        returns (address payable)
    {
        return EIP712MetaTransaction.msgSender();
    }
}
