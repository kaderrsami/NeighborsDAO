// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title NeighborGovernor
 * @notice Quadratic-weighted Governor for a DAO with multi-sig execution, Yes/No/Abstain voting, and reward integration.
 */

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "./NGT.sol"; 
import "./StreakDistributor.sol";

contract NeighborGovernor is
    Governor,
    GovernorSettings,
    GovernorVotes,
    GovernorCountingSimple,
    GovernorTimelockControl
{
    StreakDistributor public distributor;

    uint256 public constant MULTISIG_THRESHOLD = 3; // example: 3 of 5 required

    mapping(uint256 => mapping(address => bool)) public executionApprovals;
    mapping(uint256 => uint256) public executionApprovalCount;

    address[] public multisigSigners; // official city signers

    constructor(
        NeighborGovToken token,
        TimelockController timelock,
        StreakDistributor dist,
        address[] memory _signers
    )
        Governor("NeighborGovernor")
        GovernorSettings(1 days, 7 days, 0)
        GovernorVotes(token)
        GovernorTimelockControl(timelock)
    {
        distributor = dist;
        multisigSigners = _signers;
    }

    /* ───────────── Quadratic weight ───────────── */
    function _getVotes(
        address voter,
        uint256 blockNumber,
        bytes memory
    ) internal view override(Governor, GovernorVotes) returns (uint256) {
        uint256 rawVotes = super._getVotes(voter, blockNumber, "");
        uint256 z = (rawVotes + 1) / 2;
        uint256 y = rawVotes;
        while (z < y) {
            y = z;
            z = (rawVotes / z + z) / 2;
        }
        return y;
    }

    /* ───────────── Reward hook ───────────── */
    function castVote(uint256 proposalId, uint8 support)
        public
        override(Governor)
        returns (uint256)
    {
        distributor.addPoint(_msgSender());
        return super.castVote(proposalId, support);
    }

    /* ───────────── Quorum 4% ───────────── */
    function quorum(uint256 blockNumber)
        public
        view
        override(Governor)
        returns (uint256)
    {
        return (token().getPastTotalSupply(blockNumber) * 4) / 100;
    }

    /* ───────────── Proposal Threshold ───────────── */
    function proposalThreshold()
        public
        pure
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return 0;
    }

    /* ───────────── Proposal State Overrides ───────────── */
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }


    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        require(executionApprovalCount[proposalId] >= MULTISIG_THRESHOLD, "Not enough multisig approvals");
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    /* ───────────── Custom Multi-Sig Execution Approval ───────────── */
    function approveExecution(uint256 proposalId) external {
        require(_isSigner(msg.sender), "Not a multisig signer");
        require(!executionApprovals[proposalId][msg.sender], "Already approved");

        executionApprovals[proposalId][msg.sender] = true;
        executionApprovalCount[proposalId] += 1;
    }

    function _isSigner(address account) internal view returns (bool) {
        for (uint256 i = 0; i < multisigSigners.length; i++) {
            if (multisigSigners[i] == account) {
                return true;
            }
        }
        return false;
    }

    /* ───────────── Assembly (Yul) Example ───────────── */
    function _assemblyExample() internal pure returns (uint256 result) {
        assembly {
            result := add(1, 1)
        }
    }
}
