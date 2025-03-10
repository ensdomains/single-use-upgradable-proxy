// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/StorageSlot.sol";

/**
 * @title SingleTimeUpgradableProxy
 * @dev A proxy that uses CALL instead of DELEGATECALL to forward requests to an implementation.
 * Can be upgraded only once, after which admin rights are revoked.
 */
contract SingleTimeUpgradableProxy {
    // Storage slot for implementation address (EIP-1967 compatible)
    bytes32 private constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Storage slot for admin (EIP-1967 compatible)
    bytes32 private constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    // Custom errors
    error CallerNotAdmin();
    error InvalidImplementation();
    error SameImplementation();
    error ProtectedFunction();

    // Events
    event Upgraded(address indexed implementation);
    event AdminChanged(address indexed previousAdmin, address indexed newAdmin);
    event UpgradeRevoked(address indexed admin);

    /**
     * @dev Initializes the proxy with an implementation and admin.
     * @param admin_ The address of the admin
     * @param implementation_ The address of the implementation
     * @param data_ Constructor data to be passed to the implementation
     */
    constructor(address admin_, address implementation_, bytes memory data_) payable {
        _validateImplementation(implementation_);
        _setImplementation(implementation_);
        _setAdmin(admin_);

        // Initialize the implementation if there's constructor data
        if (data_.length > 0) {
            (bool success,) = implementation_.call{value: msg.value}(data_);
            require(success, "Call to implementation failed");
        }
    }

    /**
     * @dev Modifier restricting a function to the admin.
     */
    modifier onlyAdmin() {
        if (msg.sender != _getAdmin()) revert CallerNotAdmin();
        _;
    }

    /**
     * @dev Changes the implementation address and revokes admin rights.
     * @param newImplementation Address of the new implementation
     * @param data Initialization data to send to the new implementation
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable onlyAdmin {
        _validateImplementation(newImplementation);
        _setImplementation(newImplementation);

        emit Upgraded(newImplementation);

        // Initialize the new implementation
        if (data.length > 0) {
            (bool success,) = newImplementation.call{value: msg.value}(data);
            require(success, "Call to new implementation failed");
        }

        // Revoke admin rights after upgrade
        _revokeAdmin();
    }

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev Returns the current admin address.
     */
    function admin() external view returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Validates if the implementation is valid.
     */
    function _validateImplementation(address newImplementation) internal view {
        if (newImplementation.code.length == 0) revert InvalidImplementation();
        if (_getImplementation() == newImplementation) revert SameImplementation();
    }

    /**
     * @dev Revokes admin rights by setting admin to address(0).
     */
    function _revokeAdmin() internal {
        address previousAdmin = _getAdmin();
        _setAdmin(address(0));
        emit UpgradeRevoked(previousAdmin);
    }

    /**
     * @dev Sets the implementation address in storage.
     */
    function _setImplementation(address newImplementation) private {
        StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Gets the current implementation address from storage.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Sets the admin address in storage.
     */
    function _setAdmin(address newAdmin) private {
        address previousAdmin = _getAdmin();
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
        emit AdminChanged(previousAdmin, newAdmin);
    }

    /**
     * @dev Gets the current admin address from storage.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Checks if a function selector requires admin privileges.
     * @param selector The function selector to check
     * @return True if the function requires admin privileges
     */
    function _isProtectedFunction(bytes4 selector) internal pure returns (bool) {
        // List of protected function selectors
        // setGatewayURLs(string[]) selector: 0x35b8a61a
        return selector == 0x35b8a61a;
    }

    /**
     * @dev Fallback function that forwards calls to the implementation using CALL.
     * Includes admin check for protected functions.
     * This is the key difference from a DELEGATECALL proxy - it doesn't share storage.
     */
    fallback() external payable {
        address _implementation = _getImplementation();
        require(_implementation != address(0), "Implementation not set");

        // Check if this is a protected function call that requires admin privileges
        if (_isProtectedFunction(msg.sig)) {
            if (msg.sender != _getAdmin()) {
                revert ProtectedFunction();
            }
        }
        // Forward the call using CALL, not DELEGATECALL
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch space at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := call(gas(), _implementation, callvalue(), 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Receive function that forwards to the implementation.
     */
    receive() external payable {
        address _implementation = _getImplementation();
        require(_implementation != address(0), "Implementation not set");

        // Forward the call using CALL
        (bool success,) = _implementation.call{value: msg.value}("");
        require(success, "Call to implementation failed");
    }
}
