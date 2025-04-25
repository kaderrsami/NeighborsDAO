// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NGT.sol";
import "../src/NRT.sol";
import "../src/StreakDistributor.sol";



/*
   Foundry test-suite for the Neighbor token stack.
   ─────────────────────────────────────────────────
   ▸ NeighborGovTokenTest   ─ whitelisting, cap, rage-quit
   ▸ NeighborRewardTokenTest ─ annual cap, merchant burn
   ▸ StreakDistributorTest   ─ points → pool share & claim flow
*/

// ────────────────────────────────────────────────────────────
// Neighbor Governance Token (NGT) tests
// ────────────────────────────────────────────────────────────
contract NeighborGovTokenTest is Test {
    NeighborGovToken ngt;

    address registrar = vm.addr(1);
    address alice     = vm.addr(2);
    address bob       = vm.addr(3);

    uint256 constant INITIAL_SUPPLY = 1_000 ether;
    uint256 constant CAP            = 2_000 ether;

    function setUp() public {
        ngt = new NeighborGovToken(INITIAL_SUPPLY, CAP, registrar);

        // registrar → whitelist Alice & grant itself MINTER_ROLE
        vm.startPrank(registrar);
        ngt.whitelist(alice, true);
        ngt.grantRole(ngt.MINTER_ROLE(), registrar);
        ngt.mint(alice, 500 ether);
        vm.stopPrank();
    }

    function testTransferBlockedForNonEligible() public {
        // Bob is NOT whitelisted ⇒ transfer should revert
        vm.startPrank(alice);
        vm.expectRevert("transfer: not eligible");
        ngt.transfer(bob, 100 ether);
        vm.stopPrank();
    }

    function testRageQuitBurns() public {
        uint256 balanceBefore = ngt.balanceOf(alice);
        vm.prank(alice);
        ngt.rageQuit(100 ether);

        assertEq(ngt.balanceOf(alice), balanceBefore - 100 ether);
        assertEq(
            ngt.totalSupply(),
            INITIAL_SUPPLY + 500 ether - 100 ether
        );
    }

    function testCapEnforced() public {
        vm.prank(registrar);
        ngt.whitelist(bob, true);

        vm.prank(registrar);
        vm.expectRevert("cap exceeded");
        ngt.mint(bob, 1_000 ether);
    }
}

// ────────────────────────────────────────────────────────────
// Neighbor Reward Token (NRT) tests
// ────────────────────────────────────────────────────────────
contract NeighborRewardTokenTest is Test {
    NeighborRewardToken nrt;

    address treasury  = vm.addr(4);
    address merchant  = vm.addr(5);

    uint256 constant CAP = 1_000 ether;

    function setUp() public {
        nrt = new NeighborRewardToken(CAP, treasury);

        // grant MERCHANT_ROLE
        vm.prank(treasury);
        nrt.grantRole(nrt.MERCHANT_ROLE(), merchant);
    }

    function testAnnualCapResets() public {
        // Mint up to the yearly cap
        vm.startPrank(treasury);
        nrt.mint(merchant, CAP);
        vm.expectRevert("annual cap exceeded");
        nrt.mint(merchant, 1);
        vm.stopPrank();

        // warp one full year + 1 second
        vm.warp(block.timestamp + 365 days + 1);

        vm.prank(treasury);
        nrt.mint(merchant, CAP); // should succeed again
    }

    function testMerchantBurn() public {
        vm.prank(treasury);
        nrt.mint(merchant, 100 ether);

        uint256 supplyBefore = nrt.totalSupply();
        vm.prank(merchant);
        nrt.merchantBurn(50 ether, "order-42");

        assertEq(nrt.totalSupply(), supplyBefore - 50 ether);
    }
}

// ────────────────────────────────────────────────────────────
// StreakDistributor tests
// ────────────────────────────────────────────────────────────
contract StreakDistributorTest is Test {
    NeighborRewardToken nrt;
    StreakDistributor   distributor;

    address governor = vm.addr(6);
    address treasury = vm.addr(7);
    address voter1   = vm.addr(8);
    address voter2   = vm.addr(9);

    uint256 constant POOL = 1_000 ether;

    function setUp() public {
        nrt = new NeighborRewardToken(POOL, treasury);
        distributor = new StreakDistributor(nrt, governor, treasury);

        // fund & approve pool
        vm.prank(treasury);
        nrt.mint(treasury, POOL);

        vm.prank(treasury);
        nrt.approve(address(distributor), POOL);
    }

    function _castVote(address voter, uint256 times) internal {
        vm.startPrank(governor);
        for (uint256 i; i < times; ++i) {
            distributor.addPoint(voter);
        }
        vm.stopPrank();
    }

    function testClaimFlow() public {
        // 3 pts to voter1, 1 pt to voter2
        _castVote(voter1, 3);
        _castVote(voter2, 1);

        // close quarter & fund pool
        vm.prank(treasury);
        distributor.finaliseQuarter(POOL);

        uint256 share1 = (POOL * 3) / 4;
        uint256 share2 = POOL - share1;

        // voter1 claim
        vm.prank(voter1);
        distributor.claim(0);
        assertEq(nrt.balanceOf(voter1), share1);

        // voter2 claim
        vm.prank(voter2);
        distributor.claim(0);
        assertEq(nrt.balanceOf(voter2), share2);

        // second claim should revert
        vm.prank(voter1);
        vm.expectRevert("already claimed");
        distributor.claim(0);
    }
}
