pragma solidity >0.7.0;
pragma experimental ABIEncoderV2;

/// @title Logger - log whatever you need from a safe
contract Logger {
    bytes32 private constant GUARD_VALUE = keccak256("logger.guard.bytes32");
    event Message(address indexed from, bytes32 indexed bloom, bytes data);

    bytes32 guard;

    constructor() public {
        guard = GUARD_VALUE;
    }

    function log(bytes32 bloom, bytes memory data) public {
        emit Message(msg.sender, bloom, data);
    }

    function logMultiple(bytes32[] memory blooms, bytes[] memory data) public {
        for (uint256 i = 0; i < blooms.length; i++) {
            emit Message(msg.sender, blooms[i], data[i]);
        }
    }

    function callDataOnly(bytes32 bloom, bytes memory) public {
        emit Message(msg.sender, bloom, "");
    }
}
