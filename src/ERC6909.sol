// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC6909Claims} from "./interfaces/external/IERC6909Claims.sol";

/// @notice Minimalist and gas efficient standard ERC6909 implementation.
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC6909.sol)
/// @dev Copied from the commit at 4b47a19038b798b4a33d9749d25e570443520647
/// @dev This contract has been modified from the implementation at the above link.
abstract contract ERC6909 is IERC6909Claims {
    /*//////////////////////////////////////////////////////////////
                             ERC6909 STORAGE
    //////////////////////////////////////////////////////////////*/

    function isOperatorKey(address owner, address operator) internal pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(bytes4(0xb6363cf2), owner, operator));
    }

    function isOperator(address owner, address operator) public view returns (bool authorized) {
        bytes32 key = isOperatorKey(owner, operator);
        assembly ("memory-safe") {
            authorized := sload(key)
        }
    }

    function balanceOfKey(address owner, uint256 id) internal pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(bytes4(0x00fdd58e), owner, id));
    }

    function balanceOf(address owner, uint256 id) public view returns (uint256 _balance) {
        bytes32 key = balanceOfKey(owner, id);
        assembly ("memory-safe") {
            _balance := sload(key)
        }
    }

    function allowanceKey(address owner, address spender, uint256 id) internal pure returns (bytes32 key) {
        return keccak256(abi.encodePacked(bytes4(0x598af9e7), owner, spender, id));
    }

    function allowance(address owner, address spender, uint256 id) public view returns (uint256 _allowance) {
        bytes32 key = allowanceKey(owner, spender, id);
        assembly ("memory-safe") {
            _allowance := sload(key)
        }
    }

    /*//////////////////////////////////////////////////////////////
                              ERC6909 LOGIC
    //////////////////////////////////////////////////////////////*/

    function transfer(address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        {
            bytes32 senderKey = balanceOfKey(msg.sender, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(senderKey)
            }
            _balance -= amount;
            assembly ("memory-safe") {
                sstore(senderKey, _balance)
            }

        }
        {
            bytes32 receiverKey = balanceOfKey(receiver, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(receiverKey)
            }
            _balance += amount;
            assembly ("memory-safe") {
                sstore(receiverKey, _balance)
            }
        }

        emit Transfer(msg.sender, msg.sender, receiver, id, amount);

        return true;
    }

    function transferFrom(address sender, address receiver, uint256 id, uint256 amount) public virtual returns (bool) {
        if (msg.sender != sender) {
            if (!isOperator(sender, msg.sender)) {
                bytes32 _allowanceKey = allowanceKey(sender, msg.sender, id);
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

        {
            bytes32 senderKey = balanceOfKey(sender, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(senderKey)
            }
            _balance -= amount;
            assembly ("memory-safe") {
                sstore(senderKey, _balance)
            }

        }
        {
            bytes32 receiverKey = balanceOfKey(receiver, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(receiverKey)
            }
            _balance += amount;
            assembly ("memory-safe") {
                sstore(receiverKey, _balance)
            }
        }

        emit Transfer(msg.sender, sender, receiver, id, amount);

        return true;
    }

    function approve(address spender, uint256 id, uint256 amount) public virtual returns (bool) {
        bytes32 key = allowanceKey(msg.sender, spender, id);
        assembly ("memory-safe") {
            sstore(key, amount)
        }

        emit Approval(msg.sender, spender, id, amount);

        return true;
    }

    function setOperator(address operator, bool approved) public virtual returns (bool) {
        bytes32 key = isOperatorKey(msg.sender, operator);
        assembly ("memory-safe") {
            sstore(key, approved)
        }

        emit OperatorSet(msg.sender, operator, approved);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC165 LOGIC
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0x0f632fb3; // ERC165 Interface ID for ERC6909
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address receiver, uint256 id, uint256 amount) internal virtual {
        {
            bytes32 receiverKey = balanceOfKey(receiver, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(receiverKey)
            }
            _balance += amount;
            assembly ("memory-safe") {
                sstore(receiverKey, _balance)
            }
        }

        emit Transfer(msg.sender, address(0), receiver, id, amount);
    }

    function _burn(address sender, uint256 id, uint256 amount) internal virtual {
        {
            bytes32 senderKey = balanceOfKey(sender, id);
            uint256 _balance;
            assembly ("memory-safe") {
                _balance := sload(senderKey)
            }
            _balance -= amount;
            assembly ("memory-safe") {
                sstore(senderKey, _balance)
            }

        }

        emit Transfer(msg.sender, sender, address(0), id, amount);
    }
}
