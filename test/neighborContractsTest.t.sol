// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/NGT.sol";
import "../src/NRT.sol";
import "../src/StreakDistributor.sol";

contract NeighborGovTokenTest is Test {
    NeighborGovToken ngt;
    address registrar = vm.addr(1);
    address alice     = vm.addr(2);
    address bob       = vm.addr(3);

    uint256 constant INITIAL_SUPPLY = 1_000 ether;
    uint256 constant CAP            = 2_000 ether;

    function setUp() public {
        ngt = new NeighborGovToken(INITIAL_SUPPLY, CAP, registrar);

        // registrar → whitelist Alice & grant itself MINTER_ROLE + mint
        vm.startPrank(registrar);
        ngt.whitelist(alice, true);
        ngt.grantRole(ngt.MINTER_ROLE(), registrar);
        ngt.mint(alice, 500 ether);
        vm.stopPrank();
    }

    // ──────────────── Unit tests ────────────────

    function testTransferBlockedForNonEligible() public {
        vm.startPrank(alice);
        vm.expectRevert("transfer: not eligible");
        ngt.transfer(bob, 100 ether);
        vm.stopPrank();
    }

    function testCapEnforced() public {
        vm.prank(registrar);
        ngt.whitelist(bob, true);

        vm.prank(registrar);
        vm.expectRevert("cap exceeded");
        ngt.mint(bob, 1_000 ether);
    }

    // ───────────── Integration test ─────────────

    function testDelegateVotingPowerAndAccessControl() public {
        // Bob must be whitelisted to receive delegation
        vm.prank(registrar);
        ngt.whitelist(bob, true);

        // Alice delegates all her votes to Bob
        vm.prank(alice);
        ngt.delegate(bob);
        assertEq(ngt.getVotes(bob), 500 ether);

        // Attempt to delegate to a non-eligible address should revert
        address charlie = vm.addr(10);
        vm.prank(alice);
        vm.expectRevert("transfer: not eligible");
        ngt.delegate(charlie);
    }

    // ───────────── Forge‐special tests ─────────────

    /// @dev Fuzz test: rageQuit for any amount up to Alice’s balance
    function testFuzzRageQuit(uint128 amount) public {
        uint256 bal = ngt.balanceOf(alice);
        vm.assume(amount <= bal);
        uint256 totalBefore = ngt.totalSupply();

        vm.prank(alice);
        ngt.rageQuit(amount);

        assertEq(ngt.totalSupply(), totalBefore - amount);
        assertEq(ngt.balanceOf(alice), bal - amount);
    }

    /// @dev Invariant: total supply never exceeds the cap
    function invariant_totalSupplyNeverExceedsCap() public view {
        assertLe(ngt.totalSupply(), CAP);
    }
}

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

    // ──────────────── Unit tests ────────────────

    function testMerchantBurn() public {
        vm.prank(treasury);
        nrt.mint(merchant, 100 ether);

        uint256 supplyBefore = nrt.totalSupply();
        vm.prank(merchant);
        nrt.merchantBurn(50 ether, "order-42");

        assertEq(nrt.totalSupply(), supplyBefore - 50 ether);
    }

    function testMerchantBurnOnlyByMerchant() public {
        vm.prank(treasury);
        nrt.mint(merchant, 50 ether);

        address nonMerchant = vm.addr(20);
        vm.prank(nonMerchant);
        vm.expectRevert(); // missing MERCHANT_ROLE
        nrt.merchantBurn(10 ether, "nop");
    }

    // ─────────── Integration test ───────────

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

    // ─────────── Forge‐special test ───────────

    /// @dev Fuzz test: mint random amounts, expect either success or revert
    function testFuzzMintWithinAnnualCap(uint96 amount) public {
        vm.prank(treasury);
        uint256 already = nrt.mintedThisYear();
        vm.assume(amount <= CAP);
        if (already + amount <= CAP) {
            nrt.mint(merchant, amount);
            assertLe(nrt.mintedThisYear(), CAP);
        } else {
            vm.expectRevert("annual cap exceeded");
            nrt.mint(merchant, amount);
        }
    }
}

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

    // ──────────────── Unit tests ────────────────

    function testAddPointAccessControl() public {
        // Only governor may add points
        vm.expectRevert(); 
        distributor.addPoint(voter1);

        vm.prank(governor);
        distributor.addPoint(voter1);
        assertEq(distributor.points(0, voter1), 1);
    }

    function testFinaliseQuarterOnlyByTreasuryAndCannotTwice() public {
        // Must have points before finalising
        vm.prank(treasury);
        vm.expectRevert("already done");
        distributor.finaliseQuarter(100);

        // valid finalise
        _castVote(voter1, 2);
        vm.prank(treasury);
        distributor.finaliseQuarter(POOL);
        // destructure the tuple returned by the public getter
        (, , , bool quarterClosed) = distributor.quarters(0);
        assertTrue(quarterClosed);
        // cannot do it again
        vm.prank(treasury);
        vm.expectRevert("already done");
        distributor.finaliseQuarter(POOL);
    }

    // ───────────── Integration test ─────────────

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

    // ────────── Forge‐special test ──────────

    /// @dev Fuzz‐style test: random point distributions correctly split the pool
    function testFuzzShareDistribution(uint8 p1, uint8 p2) public {
        uint256 pts1 = uint256(p1) + 1;
        uint256 pts2 = uint256(p2) + 1;

        _castVote(voter1, pts1);
        _castVote(voter2, pts2);

        vm.prank(treasury);
        distributor.finaliseQuarter(POOL);

        uint256 expected1 = (POOL * pts1) / (pts1 + pts2);
        uint256 expected2 = POOL - expected1;

        vm.prank(voter1);
        distributor.claim(0);
        vm.prank(voter2);
        distributor.claim(0);

        assertEq(nrt.balanceOf(voter1), expected1);
        assertEq(nrt.balanceOf(voter2), expected2);
    }
}