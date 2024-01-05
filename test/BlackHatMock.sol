// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "../src/Bonds.sol";
import "./MockERC20.sol";
import "../lib/forge-std/src/console.sol";

contract BlackHatMock {
    Bonds bonds;
    address public lastTokenAddress;

    event AttackInitiated(address tokenAddress, uint256 value);
    event ReentrancyAttempt(uint256 value);
    event EpochBoundaryAttackInitiated(address tokenAddress, uint256 beforeEpochValue, uint256 afterEpochValue);
    
    constructor(Bonds _bonds) {
        bonds = _bonds;
    }

    function attack(address tokenAddress) public {
        lastTokenAddress = tokenAddress;
        MockERC20 mockERC20 = MockERC20(tokenAddress);
        uint256 attackValue = calculateOptimalAttackValue(tokenAddress);
        console.log("Initiating attack with value:", attackValue);
        emit AttackInitiated(tokenAddress, attackValue);
        mockERC20.approve(address(bonds), attackValue);
        try bonds.mintBond(attackValue, tokenAddress) {
            console.log("Attack mintBond call successful");
        } catch {
            console.log("Attack mintBond call failed");
        }
    }

    fallback() external payable {
        uint256 reentrancyValue = calculateReentrancyValue(lastTokenAddress);
        console.log("Attempting reentrancy with value:", reentrancyValue);
        emit ReentrancyAttempt(reentrancyValue);
        try bonds.mintBond(reentrancyValue, address(0)) {
            console.log("Reentrant mintBond call successful");
        } catch {
            console.log("Reentrant mintBond call failed");
        }
    }

    function epochBoundaryAttack(address tokenAddress, uint256 timestampJustBefore, uint256 timestampJustAfter) public {
        lastTokenAddress = tokenAddress;

        uint256 attackValueJustBefore = calculateOptimalAttackValue(tokenAddress);
        uint256 attackValueJustAfter = calculateOptimalAttackValue(tokenAddress);
        emit EpochBoundaryAttackInitiated(tokenAddress, attackValueJustBefore, attackValueJustAfter);

        executeMint(attackValueJustBefore, tokenAddress, timestampJustBefore);
        executeMint(attackValueJustAfter, tokenAddress, timestampJustAfter);
    }



    function executeMint(uint256 value, address tokenAddress, uint256 timestamp) public {
            console.log("Minting at timestamp:", timestamp);

        try bonds.mintBond(value, tokenAddress) {
            console.log("Minting successful with value:", value);
        } catch {
            console.log("Minting failed with value:", value);
        }
    }

    function calculateOptimalAttackValue(address tokenAddress) public view returns (uint256) {
        (uint256 min, uint256 max, uint256 maxSupply, uint256 totalMinted, /* another variable if needed */) = bonds.currencies(tokenAddress);
 uint256 remainingSupply = maxSupply > totalMinted ? maxSupply - totalMinted : 0;
        if (remainingSupply >= min && remainingSupply <= max) {
            return remainingSupply;
        } else if (remainingSupply > max) {
            return max;
        } else {
            return min;
        }
    }

    function calculateReentrancyValue(address tokenAddress) internal view returns (uint256) {
        (uint256 min, uint256 max, uint256 maxSupply, uint256 totalMinted, /* another variable if needed */) = bonds.currencies(tokenAddress);
        if (totalMinted >= maxSupply) {
            return 0;
        }
        uint256 attemptValue = maxSupply - totalMinted;
        if (attemptValue > max) {
            attemptValue = max;
        } else if (attemptValue < min) {
            attemptValue = min;
        }
        return attemptValue;
    }

    receive() external payable {}
}
