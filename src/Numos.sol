// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Numos (NUMOS)
/// @notice Fixed-supply community token for @Numosimd on X.
/// @dev The deployer receives the entire supply. During an IdentityMD launch this
/// is the factory, which handles the 90% pool / 10% contributor allocation.
contract Numos is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20("Numos", "NUMOS") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
