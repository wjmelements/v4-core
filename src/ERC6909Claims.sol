// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC6909} from "./ERC6909.sol";

/// @notice ERC6909Claims inherits ERC6909 and implements an internal burnFrom function
abstract contract ERC6909Claims is ERC6909 {
    /// @notice Burn `amount` tokens of token type `id` from `from`.
    /// @dev if sender is not `from` they must be an operator or have sufficient allowance.
    /// @param from The address to burn tokens from.
    /// @param id The currency to burn.
    /// @param amount The amount to burn.
    function _burnFrom(address from, uint256 id, uint256 amount) internal {
        if (from != msg.sender) {
            if (!isOperator(from, msg.sender)) {
                bytes32 _allowanceKey = allowanceKey(from, msg.sender, id);
                uint256 allowed;
                assembly ("memory-safe") {
                    allowed := sload(_allowanceKey)
                }
                if (allowed != type(uint256).max) {
                    allowed -= amount;
                    assembly ("memory-safe") {
                        sstore(_allowanceKey, allowed)
                    }
                }
            }
        }
        _burn(from, id, amount);
    }
}
