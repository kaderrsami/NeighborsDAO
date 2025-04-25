// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "src/NRT.sol";

/*───────────────────────────────────────────────────────────────────────────*\
 ░░  StreakDistributor  ░░    ─  quarterly “civic‑points” reward module   ░
\*───────────────────────────────────────────────────────────────────────────*/
contract StreakDistributor is AccessControl {
    /*----------------------------------------------------------  ROLES  */
    bytes32 public constant GOVERNOR_ROLE = keccak256("GOVERNOR_ROLE");
    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    NeighborRewardToken public immutable NRT;

    /*----------------------------------------------------------  STATE  */
    struct Quarter {
        uint256 pool;                // NRT funded by treasury
        uint256 totalPoints;         // Σ points earned this quarter
        uint256 startTime;           // inclusive
        bool    finalised;           // once true, users can claim
    }

    uint256 public currentQtr;                       // 0‑indexed counter
    mapping(uint256 => Quarter)            public quarters;
    mapping(uint256 => mapping(address=>uint256)) public points;      // qtr→user→pts
    mapping(uint256 => mapping(address=>bool))    public claimed;     // qtr→user→claimed?

    /*-----------------------------------------------------  CONSTRUCTOR  */
    constructor(NeighborRewardToken _nrt, address governor, address treasury) {
        NRT = _nrt;

        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(GOVERNOR_ROLE, governor);
        _grantRole(TREASURY_ROLE, treasury);

        quarters[0].startTime = block.timestamp;     // bootstrap Q0
    }

    /*------------------------------------------------  VOTE POINT HOOK  */
    /// @dev Governor contract calls this once per successful vote cast.
    function addPoint(address voter) external onlyRole(GOVERNOR_ROLE) {
        Quarter storage q = quarters[currentQtr];
        require(!q.finalised, "quarter closed");
        unchecked {                                   // overflow impossible
            points[currentQtr][voter] += 1;
            q.totalPoints              += 1;
        }
    }

    /*---------------------------------------------  FINALISE & FUND QTR  */
    /// @notice Treasury deposits NRT and closes the quarter for claiming.
    function finaliseQuarter(uint256 poolAmount)
        external
        onlyRole(TREASURY_ROLE)
    {
        Quarter storage q = quarters[currentQtr];
        require(!q.finalised, "already done");

        // pull tokens from treasury wallet
        require(
            NRT.transferFrom(_msgSender(), address(this), poolAmount),
            "transfer failed"
        );

        q.pool      = poolAmount;
        q.finalised = true;

        emit QuarterFinalised(currentQtr, poolAmount, q.totalPoints);

        // start next quarter
        currentQtr += 1;
        quarters[currentQtr].startTime = block.timestamp;
    }

    event QuarterFinalised(uint256 indexed qtr, uint256 pool, uint256 totalPts);

    /*-------------------------------------------------------  CLAIM  */
    function claim(uint256 qtr) external {
        Quarter storage q = quarters[qtr];
        require(q.finalised,  "not finalised");
        require(!claimed[qtr][_msgSender()], "already claimed");

        uint256 pts = points[qtr][_msgSender()];
        require(pts > 0, "no points");

        uint256 share = (q.pool * pts) / q.totalPoints;
        claimed[qtr][_msgSender()] = true;

        require(NRT.transfer(_msgSender(), share), "payout failed");
        emit Claimed(qtr, _msgSender(), share);
    }

    event Claimed(uint256 indexed qtr, address indexed user, uint256 amount);
}

