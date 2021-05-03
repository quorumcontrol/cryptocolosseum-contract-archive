// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155Receiver.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "./libraries/UniswapV2Library.sol";

import "./interfaces/IAssets.sol";
import "./interfaces/IAssetsERC20Wrapper.sol";
import "./interfaces/IGameEquipment.sol";
import "hardhat/console.sol";

interface IWrapperFactory {
    function getWrapper(uint256 tokenID) external view returns (address); // mapping of tokenID to address

    function createWrapper(
        uint256 tokenID,
        string calldata name,
        string calldata symbol
    ) external returns (address);
}

contract Marketplace is Ownable, ERC1155Receiver {
    using SafeMath for uint256;

    event Bootstrap(uint256 indexed itemID, uint256 prestigeAmount, uint256 tokenAmount);
    event Mint(uint256 indexed itemID, uint256 quantity);
    event Buy(address indexed from, uint256 indexed itemID, uint256 prestigeAmount, uint256 tokenAmount);
    event Sell(address indexed from, uint256 indexed itemID, uint256 prestigeAmount, uint256 tokenAmount);

    uint256 constant maxUint = 2**254;
    bytes4 constant bootstrapSelector = bytes4(keccak256("boot"));

    uint256 private immutable _ptgID;
    IAssets private immutable _assets;
    IGameEquipment private immutable _equipment;
    IWrapperFactory private immutable _wrapperFactory;
    IAssetsERC20Wrapper public immutable wrappedPTG;
    IUniswapV2Factory public immutable uniswapFactory;
    IUniswapV2Router02 public immutable uniswapRouter;

    constructor(
        address assetsContract,
        address equipmentContract,
        address wrapperFactoryContract,
        address uniswapFactoryContract,
        address uniswapRouterContract,
        uint256 ptgID
    ) {
        IWrapperFactory factory = IWrapperFactory(wrapperFactoryContract);
        _wrapperFactory = factory;
        _assets = IAssets(assetsContract);

        // you cannot call getWrapper here because you can't read from _wrapperFactory;
        address wrapperContract = factory.getWrapper(ptgID);
        require(wrapperContract != address(0), "invalid token wrapper");
        wrappedPTG = IAssetsERC20Wrapper(wrapperContract);

        uniswapFactory = IUniswapV2Factory(uniswapFactoryContract);
        uniswapRouter = IUniswapV2Router02(uniswapRouterContract);

        IAssetsERC20Wrapper(wrapperContract).approve(
            uniswapRouterContract,
            maxUint
        );
        _equipment = IGameEquipment(equipmentContract);
        _ptgID = ptgID;
    }

    function prices(uint itemID, uint quantity) external view returns (uint buy, uint sell) {
        address itemWrapper = _wrapperFactory.getWrapper(itemID);
        (uint ptgReserve, uint itemReserve) = UniswapV2Library.getReserves(address(uniswapFactory), address(wrappedPTG), itemWrapper);
        buy = 0;
        // do not error if trying to buy more than allowed, you can never buy *all* the items (because price would be infinite)
        if (itemReserve > quantity) {
            buy = UniswapV2Library.getAmountIn(quantity, ptgReserve, itemReserve);
        }
        sell = UniswapV2Library.getAmountOut(quantity, itemReserve, ptgReserve);
        return (buy,sell);
    }

    function wrapper(uint itemID) external view returns (address) {
        return _wrapperFactory.getWrapper(itemID);
    }

    function reserves(uint itemID) external view returns (uint ptg, uint item) {
        address itemWrapper = _wrapperFactory.getWrapper(itemID);
        return UniswapV2Library.getReserves(address(uniswapFactory), address(wrappedPTG), itemWrapper);
    }

    function bootstrap(
        uint256 tokenID,
        uint256 prestigeAmount,
        uint256 tokenAmount,
        string memory name,
        string memory symbol
    ) internal {
        // create the item proxy, and the liquidity pool
        // TODO: add to a list of items
        IAssetsERC20Wrapper tokenWrapper =
            IAssetsERC20Wrapper(
                _wrapperFactory.createWrapper(tokenID, name, symbol)
            );
        tokenWrapper.approve(address(uniswapRouter), maxUint);
        _assets.safeTransferFrom(
            address(this),
            address(tokenWrapper),
            tokenID,
            tokenAmount,
            ""
        );
        _assets.safeTransferFrom(
            address(this),
            address(wrappedPTG),
            _ptgID,
            prestigeAmount,
            ""
        );

        uniswapRouter.addLiquidity(
            address(wrappedPTG),
            address(tokenWrapper),
            prestigeAmount,
            tokenAmount,
            prestigeAmount,
            tokenAmount,
            address(this),
            maxUint
        );
        emit Bootstrap(tokenID, prestigeAmount, tokenAmount);
    }

    function getWrapper(uint256 tokenID)
        internal
        view
        returns (IAssetsERC20Wrapper)
    {
        address wrapperContract = _wrapperFactory.getWrapper(tokenID);
        require(wrapperContract != address(0), "invalid token wrapper");
        return IAssetsERC20Wrapper(wrapperContract);
    }

    function onMint(uint256 tokenID, uint256 amount) internal {
        // console.log('on mint');
        IAssetsERC20Wrapper tokenWrapper = getWrapper(tokenID);
        // console.log('wrapper: ', address(tokenWrapper));
        IUniswapV2Pair pair =
            IUniswapV2Pair(
                uniswapFactory.getPair(
                    address(tokenWrapper),
                    address(wrappedPTG)
                )
            );

        // console.log('pair: ', address(pair));
        // first we wrap them
        _assets.safeTransferFrom(
            address(this),
            address(tokenWrapper),
            tokenID,
            amount,
            ""
        );
                // console.log('wrapped');
        // then we transfer them to the liquidity contract
        tokenWrapper.transfer(address(pair), amount);
        // console.log('transferred to pair');
        // then we sync so no skim!
        pair.sync();
        // console.log('synced');
        emit Mint(tokenID, amount);
    }

    // onReceivedItem sells the item into the bonding curve
    function onReceivedItem(
        address from,
        uint256 tokenID,
        uint256 quantity,
        uint256 minAmountOut,
        uint256 deadline
    ) internal returns (uint256 amountReceived) {
        IAssetsERC20Wrapper tokenWrapper = getWrapper(tokenID);

        // first we wrap the item
        _assets.safeTransferFrom(
            address(this),
            address(tokenWrapper),
            tokenID,
            quantity,
            ""
        );
        // then we use the router
        address[] memory path = new address[](2);
        path[0] = address(tokenWrapper);
        path[1] = address(wrappedPTG);

        uint256[] memory amounts =
            uniswapRouter.swapExactTokensForTokens(
                quantity,
                minAmountOut,
                path,
                address(this),
                deadline
            );
        // now unwrap the PTG
        wrappedPTG.unwrap(address(this), from, amounts[1]);
        emit Sell(from, tokenID, amounts[0], quantity);
        return amounts[0];
    }

    // onReceivedItem buys an item with a max amount of PTG
    function onReceivedPTG(
        address from,
        uint256 amount,
        uint256 itemToBuy,
        uint256 quantity,
        uint256 maxAmount,
        uint256 deadline
    ) internal returns (uint256 amountReceived) {
        // console.log('on received ptg');
        IAssetsERC20Wrapper toBuyWrapper = getWrapper(itemToBuy);

        // first we wrap the ptg
        _assets.safeTransferFrom(
            address(this),
            address(wrappedPTG),
            _ptgID,
            amount,
            ""
        );
        // console.log('wrapped');

        // then we use the router
        address[] memory path = new address[](2);
        path[0] = address(wrappedPTG);
        path[1] = address(toBuyWrapper);

        // console.log('deadline, now', deadline, block.timestamp);

        uint256[] memory amounts =
            uniswapRouter.swapTokensForExactTokens(
                quantity,
                maxAmount,
                path,
                address(this),
                deadline
            );
        // console.log('swapped');
        // now unwrap the item
        toBuyWrapper.unwrap(address(this), from, quantity);
        // console.log('unwrapped');

        if (amounts[0] < amount) {
            wrappedPTG.unwrap(address(this), from, amount.sub(amounts[0]));
        }
        // console.log('emit');
        emit Buy(from, itemToBuy, amounts[0], quantity);
        return amounts[0];
    }

    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override returns (bytes4) {
        uint256[] memory ids = new uint256[](1);
        uint256[] memory values = new uint256[](1);
        ids[0] = id;
        values[0] = value;
        onERC1155BatchReceived(operator, from, ids, values, data);
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address, //operator
        address from,
        uint256[] memory ids,
        uint256[] memory values,
        bytes calldata data
    ) public override returns (bytes4) {
        require(
            msg.sender == address(_assets),
            "Marketplace can only receive items from Assets contract"
        );
        // special case where we want to bootstrap and create a new pair
        if (bytes4(keccak256(abi.encodePacked(data))) == bootstrapSelector) {
            require(ids[0] == _ptgID, "first asset must be PTG");
            require(
                ids.length == 2,
                "pass in only PTG and a single other token"
            );
            IGameEquipment.EquipmentMetadata memory meta =
                _equipment.getMetadata(ids[1]);

            bootstrap(
                ids[1],
                values[0],
                values[1],
                meta.name,
                string(abi.encodePacked("CCWRAP-", uint2str(ids[1])))
            );
            return IERC1155Receiver.onERC1155BatchReceived.selector;
        }

        for (uint256 i; i < ids.length; i++) {
            if (from == address(0)) {
                // this is a mint
                onMint(ids[i], values[i]);
                continue;
            }
            if (ids[i] == _ptgID) {
                // this is a *purchase* of an item
                require(ids.length == 1, "cannot batch send more if purchasing");
                (uint256 tokenID, uint256 quantity, uint256 maxPrice, uint256 deadline) = abi.decode(data, (uint256, uint256, uint256, uint256));
                onReceivedPTG(from, values[i], tokenID, quantity, maxPrice, deadline);
                break;
            }
            (uint256 minAmountOut, uint256 deadline) = abi.decode(data, (uint256, uint256));
            onReceivedItem(from, ids[i], values[i], minAmountOut, deadline);
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function uint2str(uint256 _i)
        internal
        pure
        returns (string memory _uintAsString)
    {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len - 1;
        while (_i != 0) {
            bstr[k--] = bytes1(uint8(48 + (_i % 10)));
            _i /= 10;
        }
        return string(bstr);
    }
}
