// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StreakDistributor
 * @notice Quarterly module that converts voting "points" into a share of an
 *         NRT pool.  Governor calls `addPoint()` per successful vote.
 * @dev    ✅ AUDIT-FIX: tracks claimed amounts & allows Treasury to sweep the
 *         unclaimed remainder after a grace period, preventing dust-lock.
 */

import {AccessControl}          from "@openzeppelin/contracts/access/AccessControl.sol";
import {NeighborRewardToken}    from "./NRT.sol";

contract StreakDistributor is AccessControl {
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    NeighborRewardToken public immutable NRT;

    struct Quarter {
        uint256 pool;
        uint256 totalPoints;
        uint256 claimed;     // ✅ NEW — amount already paid out
        uint256 startTime;
        bool    finalised;
    }

    uint256 public currentQtr;
    mapping(uint256 => Quarter) public quarters;
    mapping(uint256 => mapping(address => uint256)) public points;
    mapping(uint256 => mapping(address => bool))    public claimed;

    event QuarterFinalised(uint256 qtr, uint256 pool, uint256 totalPts);
    event Claimed(uint256 qtr, address user, uint256 amount);
    event RemainderSwept(uint256 qtr, uint256 amount);

    constructor(NeighborRewardToken _nrt, address governor, address treasury) {
        NRT = _nrt;

        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(GOVERNOR_ROLE,      governor);
        _grantRole(TREASURY_ROLE,      treasury);

        quarters[0].startTime = block.timestamp;
    }

    /* ─────────── Called by Governor per vote ─────── */
    function addPoint(address voter) external onlyRole(GOVERNOR_ROLE) {
        Quarter storage q = quarters[currentQtr];
        require(!q.finalised, "quarter closed");
        unchecked { points[currentQtr][voter] += 1; q.totalPoints += 1; }
    }

    /* ─────────── Treasury closes quarter & funds ─── */
    function finaliseQuarter(uint256 poolAmt) external onlyRole(TREASURY_ROLE) {
        Quarter storage q = quarters[currentQtr];
        require(!q.finalised, "already done");

        require(NRT.transferFrom(msg.sender, address(this), poolAmt), "transfer failed");

        q.pool      = poolAmt;
        q.finalised = true;

        emit QuarterFinalised(currentQtr, poolAmt, q.totalPoints);

        currentQtr += 1;
        quarters[currentQtr].startTime = block.timestamp;
    }

    /* ─────────── Residents claim share ───────────── */
    function claim(uint256 qtr) external {
        Quarter storage q = quarters[qtr];
        require(q.finalised, "not finalised");
        require(!claimed[qtr][msg.sender], "already claimed");

        uint256 pts = points[qtr][msg.sender];
        require(pts > 0, "no points");

        uint256 share = (q.pool * pts) / q.totalPoints;
        claimed[qtr][msg.sender] = true;
        q.claimed += share;                       // ✅ track paid out

        require(NRT.transfer(msg.sender, share), "payout failed");
        emit Claimed(qtr, msg.sender, share);
    }

    /* ─────────── Sweep leftover dust ───────────────
     *  Can be called by Treasury 90 days after quarter start.
     */
    function sweepRemainder(uint256 qtr, address to) external onlyRole(TREASURY_ROLE) {
        Quarter storage q = quarters[qtr];
        require(q.finalised, "not finalised");
        require(block.timestamp >= q.startTime + 90 days, "grace");

        uint256 due  = q.pool - q.claimed;
        require(due > 0, "nothing left");

        q.claimed = q.pool;                       // mark fully claimed
        require(NRT.transfer(to, due), "transfer failed");
        emit RemainderSwept(qtr, due);
    }
}
