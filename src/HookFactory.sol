// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
/// CREATE2 factory: a v4 hook only works if its address carries its permission bits.
contract HookFactory {
    event Deployed(address addr);
    function deploy(bytes32 salt, bytes memory initCode) external returns (address a) {
        assembly { a := create2(0, add(initCode, 0x20), mload(initCode), salt) }
        require(a != address(0), "create2");
        emit Deployed(a);
    }
}
