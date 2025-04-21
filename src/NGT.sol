// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title Neighbor Governance Token (NGT)
 * @notice Non‑transferable outside a whitelisted set of KYC‑verified
 *         city residents; supports COMP/UNI‑style delegation, single‑shot
 *         “rage‑quit” burn, gas‑less approvals and OZ Governor compatibility.
 */
contract NeighborGovToken is
    ERC20,
    ERC20Burnable,
    ERC20Permit,
    ERC20Votes,
    AccessControl
{
    /* ───────────────────────── ROLES ────────────────────────── */
    bytes32 public constant MINTER_ROLE    = keccak256("MINTER_ROLE");
    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");

    /* ───────────────────────── STATE ────────────────────────── */
    uint256 public immutable CAP;                 // hard cap on supply
    mapping(address => bool) private _eligible;   // simple allow‑list

    /* ────────────────────── CONSTRUCTOR ────────────────────── */
    constructor(
        uint256 initialSupply,
        uint256 _cap,
        address cityRegistrar       // multisig that manages whitelist + treasury
    )
        ERC20("Neighbor Governance Token", "NGT")
        ERC20Permit("Neighbor Governance Token")
    {
        require(_cap > 0, "cap 0");
        CAP = _cap;

        // bootstrap roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE,          msg.sender);
        _grantRole(WHITELIST_ROLE,       cityRegistrar);

        // registrar is always eligible
        _eligible[cityRegistrar] = true;

        // first mint goes to registrar treasury
        _mint(cityRegistrar, initialSupply);
        require(totalSupply() <= CAP, "cap exceeded");
    }

    /* ────────────────  MINTING & WHITELIST  ───────────────── */
    function whitelist(address resident, bool allowed)
        external
        onlyRole(WHITELIST_ROLE)
    {
        _eligible[resident] = allowed;
    }

    function mint(address to, uint256 amount)
        external
        onlyRole(MINTER_ROLE)
    {
        require(totalSupply() + amount <= CAP, "cap exceeded");
        require(_eligible[to], "not whitelisted");
        _mint(to, amount);
    }

    /* ──────────────────────  RAGE‑QUIT  ────────────────────── */
    /// @notice Burn caller’s tokens & automatically update their voting power
    function rageQuit(uint256 amount) external {
        _burn(_msgSender(), amount);
    }

    /* ────────────────  OZ v5 HOOK OVERRIDES  ──────────────── */

    /// @dev Single hook that replaces before+after‑TokenTransfer in OZ v5
    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        // allow mint (from == 0) and burn (to == 0) without eligibility checks
        if (from != address(0) && to != address(0)) {
            require(_eligible[from] && _eligible[to], "transfer: not eligible");
        }
        super._update(from, to, value);
    }

/// @dev Resolve the multiple‑inheritance clash for `nonces`
function nonces(address owner)
    public
    view
    override(ERC20Permit, Nonces)
    returns (uint256)
{
    return super.nonces(owner);
}


    /* ─────────── Required by Solidity, no additional logic ─────────── */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
