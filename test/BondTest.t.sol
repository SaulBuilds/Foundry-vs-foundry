// SPDX-License-Identifier: MIT


//these tests are an audit performed for consultation purpose. 
//implementation of a mitigation strategy can be in the README.md
pragma solidity ^0.8.15;

import "../lib/forge-std/src/Test.sol";
import "../src/BondBase.sol";
import "../src/Bonds.sol";
import "./MockERC20.sol";
import "./MockUSDC.sol";
import "./BlackHatMock.sol";

contract BondsTest is Test {
    Bonds bonds;
    MockERC20 mockERC20;
    MockUSDC mockUSDC;
    BlackHatMock blackHat;
    address deployer;

    event StateChanged(uint256 totalMinted);

    function setUp() public {
        deployer = address(this);
        uint256 maxEpoch = 1 days;
        uint256 endEpoch = 365 days;

        bonds = new Bonds(deployer, deployer, maxEpoch, endEpoch);
        mockERC20 = new MockERC20("mether", "mETH");
        mockUSDC = new MockUSDC();
        blackHat = new BlackHatMock(Bonds(address(bonds)));

        vm.startPrank(deployer);
        bonds.addCurrency(address(0));
        vm.stopPrank();

        uint256 mintAmount = 1000000000 ether;
        mockERC20.mint(address(this), mintAmount);
        mockERC20.mint(address(blackHat), mintAmount);

        vm.prank(address(blackHat));
        mockERC20.approve(address(bonds), mintAmount);

        vm.startPrank(deployer);
        bonds.addCurrency(address(mockERC20));
        vm.stopPrank();

        uint256 maxSupply = 10000000000 ether;
        uint256 interestRate = 5;
        uint256 minimum = 1 ether;
        uint256 maximum = 1000 ether;
        uint256 marketPrice = 1 ether;

        vm.startPrank(deployer);
        bonds.addCurrencyDetails(
            address(mockERC20),
            minimum,
            maximum,
            maxSupply,
            interestRate,
            marketPrice
        );
        vm.stopPrank();

        vm.startPrank(deployer);
        bonds.toggleWhitelist(deployer);
        vm.stopPrank();
    }

        // Test minting with valid parameters
    function testMintBondValidParameters() public {
        uint256 mintValue = 500 ether; // Within the valid range defined in setUp()

        mockERC20.approve(address(bonds), mintValue);
        bonds.mintBond(mintValue, address(mockERC20));

        (, , , uint256 totalMinted, ) = bonds.currencies(address(mockERC20));
        assertTrue(totalMinted >= mintValue, "Bond minting failed with valid parameters");
    }

    // Test minting with invalid parameters
    function testMintBondInvalidParameters() public {
        uint256 invalidMintValue = 1000001 ether; // Exceeds the maximum defined in setUp()
        mockERC20.approve(address(bonds), invalidMintValue);

        vm.expectRevert("Maximum limit reached");
        bonds.mintBond(invalidMintValue, address(mockERC20));
    }

    // Test minting when the contract is paused
    function testMintBondWhenPaused() public {
        uint256 mintValue = 500 ether;
        mockERC20.approve(address(bonds), mintValue);

        vm.startPrank(deployer);
        bonds.togglePaused(); // Pause the contract
        vm.stopPrank();

        vm.expectRevert("Contract is paused");
        bonds.mintBond(mintValue, address(mockERC20));
    }

    // Test minting with a non-whitelisted user when restricted minting is enabled
    function testMintBondNonWhitelistedUser() public {
        uint256 mintValue = 500 ether;
        address nonWhitelistedUser = address(2);
        mockERC20.mint(nonWhitelistedUser, mintValue);

        // Approving the bonds contract to spend tokens on behalf of the non-whitelisted user
        vm.prank(nonWhitelistedUser);
        mockERC20.approve(address(bonds), mintValue);

        vm.startPrank(deployer);
        bonds.toggleRestricted(); // Enable restricted minting
        vm.stopPrank();

        vm.expectRevert("Not whitelisted");
        vm.prank(nonWhitelistedUser); // Impersonating the non-whitelisted user for the mintBond call
        bonds.mintBond(mintValue, address(mockERC20));
    }
     // Test to verify epoch change impacts bond interest calculation
    function testEpochChangeAffectsInterestCalculation() public {
        // Setup: Mint a bond
        uint256 mintValue = 100 ether;
        mockERC20.approve(address(bonds), mintValue);
        bonds.mintBond(mintValue, address(mockERC20));
        uint256 bondId = bonds.tokenIdCounter() - 1;

        // Store initial bond value for comparison
        uint256 initialBondValue = bonds.getBondValue(bondId);

        // Action: Move forward to the next epoch
        uint256 timeTillNextEpoch = estimateTimeTillNextEpoch();
        vm.warp(block.timestamp + timeTillNextEpoch);

        // Assertions: Check if the bond value has increased due to interest accrual
        uint256 newBondValue = bonds.getBondValue(bondId);
        assertTrue(newBondValue > initialBondValue, "Bond value should increase after epoch change");
    }

    // Test to verify interest accrual stops after the end epoch
    function testInterestAccrualStopsAfterEndEpoch() public {
        // Setup: Mint a bond and warp to just before end epoch
        uint256 mintValue = 100 ether;
        mockERC20.approve(address(bonds), mintValue);
        bonds.mintBond(mintValue, address(mockERC20));
        uint256 bondId = bonds.tokenIdCounter() - 1;
        vm.warp(bonds.endEpoch() - 1);

        // Store bond value just before the end epoch
        uint256 bondValueBeforeEndEpoch = bonds.getBondValue(bondId);

        // Action: Move forward past the end epoch
        vm.warp(bonds.endEpoch() + 1);

        // Assertions: Check if the bond value remains the same
        uint256 bondValueAfterEndEpoch = bonds.getBondValue(bondId);
        assertEq(bondValueAfterEndEpoch, bondValueBeforeEndEpoch, "Bond value should not increase after end epoch");
    }

        // Test toggling admin status by super admin
    function testToggleAdminStatus() public {
        address newAdmin = address(1);
        
        vm.startPrank(deployer); // Assuming deployer is the super admin
        bonds.toggleAdminStatus(newAdmin);
        vm.stopPrank();

        assertTrue(bonds.admin(newAdmin), "Admin status not toggled correctly");
    }

    // Test calling admin functions with unauthorized user
    function testAdminFunctionsWithUnauthorizedUser() public {
        address unauthorizedUser = address(2);

        vm.startPrank(unauthorizedUser);
        vm.expectRevert("Not a superAdmin"); // Adjusted the expected error message
        bonds.toggleAdminStatus(address(3));
        vm.stopPrank();
    }


    // Test renouncing super admin role
    function testRenounceSuperAdmin() public {
        address newAdmin = address(1);

        vm.startPrank(deployer); // Assuming deployer is the current super admin
        bonds.renounceSuperAdmin(newAdmin);
        vm.stopPrank();

        assertEq(bonds.superAdmin(), newAdmin, "Super admin role not transferred correctly");
    }

    // Test bond value calculations over different epochs
    function testBondValueCalculation() public {
        uint256 mintValue = 100 ether;
        mockERC20.approve(address(bonds), mintValue);
        bonds.mintBond(mintValue, address(mockERC20));
        uint256 bondId = bonds.tokenIdCounter() - 1;

        uint256 initialBondValue = bonds.getBondValue(bondId);
        vm.warp(block.timestamp + 30 days); // Simulate time passage

        uint256 updatedBondValue = bonds.getBondValue(bondId);
        assertTrue(updatedBondValue > initialBondValue, "Bond value calculation incorrect");
    }

    // Test getCurrentEpoch function
    function testGetCurrentEpoch() public {
        uint256 currentEpoch = bonds.getCurrentEpoch();
        uint256 expectedEpoch = (block.timestamp - bonds.startEpoch()) / bonds.maxEpoch();
        assertEq(currentEpoch, expectedEpoch, "Current epoch calculated incorrectly");
    }

    // Test tokenURI function
    function testTokenURI() public {
        uint256 mintValue = 100 ether;
        mockERC20.approve(address(bonds), mintValue);
        bonds.mintBond(mintValue, address(mockERC20));
        uint256 bondId = bonds.tokenIdCounter() - 1;

        string memory expectedURI = "https://ipfs.io/ipfs/QmQS1m3JmJwL8KCrXnu4cRgzp1T7HJmN9d22cKajnJo9uA";
        assertEq(bonds.tokenURI(bondId), expectedURI, "Incorrect token URI");
    }


    function testMintBondWithFuzzing(uint256 value) public {
        if (!isValidValue(value, address(mockERC20))) return;

        mockERC20.approve(address(bonds), value);
        (
            uint256 min,
            uint256 max,
            uint256 maxSupply,
            uint256 initialTotalMinted,
        ) = bonds.currencies(address(mockERC20));
        assertTrue(value >= min && value <= max);
        assertTrue(initialTotalMinted + value <= maxSupply);

        try bonds.mintBond(value, address(mockERC20)) {
            (, , , uint256 newTotalMinted, ) = bonds.currencies(
                address(mockERC20)
            );
            assertEq(newTotalMinted, initialTotalMinted + value);
        } catch {
            (, , , uint256 newTotalMinted, ) = bonds.currencies(
                address(mockERC20)
            );
            assertEq(newTotalMinted, initialTotalMinted);
        }
    }
    //This test should fail if reentrancy attack fails. 
    //Passing test highlights a problem. 
    function testReentrancyAttack() public {
        uint256 attackValue = calculateOptimalAttackValue(address(mockERC20));
        (, , , uint256 initialTotalMinted, ) = bonds.currencies(address(mockERC20));
        mockERC20.transfer(address(blackHat), attackValue);

        // Execute reentrancy attack
        blackHat.attack(address(mockERC20));

        // Check total minted after attack
        (, , , uint256 updatedTotalMinted, ) = bonds.currencies(address(mockERC20));

        // The test passes if the total minted amount has increased after the attack,
        // indicating a successful reentrancy attack.
        assertTrue(updatedTotalMinted > initialTotalMinted, "Reentrancy attack did not succeed");
    }

    function estimateTimeTillNextEpoch() internal view returns (uint256) {
        uint256 currentEpoch = (block.timestamp - bonds.startEpoch()) /
            bonds.maxEpoch();
        uint256 nextEpochStartTime = bonds.startEpoch() +
            (currentEpoch + 1) *
            bonds.maxEpoch();
        return nextEpochStartTime - block.timestamp;
    }

    //passing test highlights a problem in the epoch transistion.
    function testEpochBoundaryAttack() public {
        uint256 attackValue = blackHat.calculateOptimalAttackValue(
            address(mockERC20)
        );
        mockERC20.transfer(address(blackHat), attackValue);

        uint256 timeTillNextEpoch = estimateTimeTillNextEpoch();
        uint256 timestampJustBefore = block.timestamp + timeTillNextEpoch - 1;
        uint256 timestampJustAfter = timestampJustBefore + 2;

        // Destructure the tuple to access the totalMinted field
        (, , , , uint256 initialTotalMinted) = bonds.currencies(
            address(mockERC20)
        );
        uint256 initialEpoch = bonds.getCurrentEpoch();

          // Mint just before the epoch boundary
    vm.warp(timestampJustBefore);
    blackHat.executeMint(
        attackValue,
        address(mockERC20),
        timestampJustBefore
    );

    // Check total minted after first mint
    (, , , , uint256 totalMintedAfterFirstMint) = bonds.currencies(address(mockERC20));
    assertTrue(totalMintedAfterFirstMint >= initialTotalMinted, "Total minted should not decrease");

    // Mint just after the epoch boundary
    vm.warp(timestampJustAfter);
    blackHat.executeMint(
        attackValue,
        address(mockERC20),
        timestampJustAfter
    );

    // Check total minted after second mint
    (, , , , uint256 totalMintedAfterSecondMint) = bonds.currencies(address(mockERC20));
    assertTrue(totalMintedAfterSecondMint >= totalMintedAfterFirstMint, "Total minted should not decrease");

    }

    function calculateOptimalAttackValue(
        address tokenAddress
    ) internal view returns (uint256) {
        (
            uint256 min,
            uint256 max,
            uint256 maxSupply,
            uint256 totalMinted,

        ) = bonds.currencies(tokenAddress);
        uint256 possibleValue = maxSupply > totalMinted
            ? maxSupply - totalMinted
            : 0;
        if (possibleValue > max) {
            return max;
        } else if (possibleValue < min) {
            return min;
        }
        return possibleValue;
    }

    function isValidValue(
        uint256 value,
        address currency
    ) internal view returns (bool) {
        (
            uint256 min,
            uint256 max,
            uint256 maxSupply,
            uint256 totalMinted,

        ) = bonds.currencies(currency);
        return value >= min && value <= max && totalMinted + value <= maxSupply;
    }
}
