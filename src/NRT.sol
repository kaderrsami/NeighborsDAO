// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/*───────────────────────────────────────────────────────────────────────────*\
 ░░  Neighbor Reward Token  ░░    ─  fungible coupon that is burned on use  ░
\*───────────────────────────────────────────────────────────────────────────*/
contract NeighborRewardToken is ERC20Burnable, AccessControl {
    /*----------------------------------------------------------  ROLES  */
    bytes32 public constant TREASURY_ROLE  = keccak256("TREASURY_ROLE");
    bytes32 public constant MERCHANT_ROLE  = keccak256("MERCHANT_ROLE");

    /*----------------------------------------------------------  STATE  */
    uint256 public immutable CAP;               // annual cap set in ctor
    uint256 public mintedThisYear;              // tracks budget envelope
    uint256 public yearStart;                   // UNIX epoch of budget year

    /*----------------------------------------------------  CONSTRUCTOR  */
    constructor(
        uint256 annualCap,
        address treasury
    )
        ERC20("Neighbor Reward Token", "NRT")
    {
        CAP       = annualCap;
        yearStart = _startOfYear(block.timestamp);

        _grantRole(DEFAULT_ADMIN_ROLE, treasury);
        _grantRole(TREASURY_ROLE,        treasury);
    }

    /*---------------------------------------------------  MINT LOGIC  */
    function mint(address to, uint256 amount)
        external
        onlyRole(TREASURY_ROLE)
    {
        _rollYear();
        require(mintedThisYear + amount <= CAP, "annual cap exceeded");
        mintedThisYear += amount;
        _mint(to, amount);
    }

    /*---------------------------------------------------  MERCHANT BURN  */
    /// @notice merchant redeems NRT and logs a memo (e.g. orderId)
    function merchantBurn(uint256 amount, string calldata memo)
        external
        onlyRole(MERCHANT_ROLE)
    {
        _burn(_msgSender(), amount);
        emit Redeemed(_msgSender(), amount, memo);
    }

    event Redeemed(address indexed merchant, uint256 amount, string memo);

    /*---------------------------------------------------  YEAR ROLL‑OVER  */
    function _rollYear() internal {
        if (block.timestamp >= yearStart + 365 days) {
            // move to next fiscal year
            uint256 yearsPassed = (block.timestamp - yearStart) / 365 days;
            yearStart          += yearsPassed * 365 days;
            mintedThisYear      = 0;
        }
    }

    function _startOfYear(uint256 ts) private pure returns (uint256) {
        return ts - (ts % 365 days);
    }
}