// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";
import "./interfaces/IAssets.sol";
import "./interfaces/IAssetsERC20Wrapper.sol";

import "hardhat/console.sol";

// turns out the regular wrapper factory doesn't support name, but this does.

contract WrappedPTG is IAssetsERC20Wrapper, ERC20, ERC1155Receiver {
    using SafeMath for uint256;

    IAssets immutable _tokenHolder;
    uint256 private _tokenID; // the specific token id this erc20 is wrapping

    mapping(address => mapping(address => uint256)) private _allowances;

    constructor(address holder, uint256 prestigeID)
        ERC20("Wrapped Prestige", "wPTG")
    {
        _tokenHolder = IAssets(holder);
        _tokenID = prestigeID; // initialize the contract for the copy
    }

    function unwrap(
        address account,
        address to,
        uint256 amount
    ) external override {
        if (account != _msgSender()) {
            uint256 currentAllowance = allowance(account, _msgSender());
            require(
                currentAllowance >= amount,
                "AssetsERC20Wrapper: unwrap amount exceeds allowance"
            );
            _approve(account, _msgSender(), currentAllowance.sub(amount));
        }
        _burn(account, amount);
        _tokenHolder.safeTransferFrom(address(this), to, _tokenID, amount, "");
    }

    function onERC1155Received(
        address, // operator
        address from,
        uint256 id,
        uint256 value,
        bytes calldata // data
    ) external override returns (bytes4) {
        require(
            msg.sender == address(_tokenHolder),
            "AssetsERC20Wrapper#onERC1155: invalid asset address"
        );
        require(id == _tokenID, "AssetsERC20Wrapper: invalid token id");

        _mint(from, value);

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] memory,
        uint256[] memory,
        bytes calldata
    ) public pure override returns (bytes4) {
        revert("batch send is not supported");
    }
}
