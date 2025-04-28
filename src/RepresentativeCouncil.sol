// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title RepresentativeCouncil
 * @notice Multisig “city council” that decides whether a proposal reaches the
 *         Governor. Signature threshold depends on impact level.
 * @dev    ✅ AUDIT-FIX: the proposal-hash now includes the governor address
 *         and impact flag, eliminating the spoof / cross-governor DoS vectors.
 */

contract RepresentativeCouncil {
    enum Impact { Minor, Major }

    uint8 public constant MINOR_THRESH = 2;
    uint8 public constant MAJOR_THRESH = 4;

    address[] public members;

    mapping(bytes32 => uint8) public sigCount;
    mapping(bytes32 => mapping(address => bool)) public signed;
    mapping(bytes32 => bool) public executed;

    event Signed(bytes32 indexed hash, address indexed signer, uint8 count);

    constructor(address[] memory _members) {
        require(_members.length >= 3 && _members.length <= 10, "bad size");
        members = _members;
    }

    modifier onlyMember() {
        bool ok;
        for (uint i; i < members.length; ++i) if (members[i] == msg.sender) ok = true;
        require(ok, "not council");
        _;
    }

    /**
     * @dev Each member calls with identical calldata until threshold met,
     *      then the call is forwarded to the Governor.
     * @param governor  Target Governor contract address.
     * @param impact    Impact level (determines threshold).
     * @param data      Encoded Governor.propose(…) call.
     */
    function signAndForward(
        address governor,
        Impact impact,
        bytes calldata data
    ) external onlyMember {
        // ✅ FIX — hash binds {governor, impact, data}
        bytes32 h = keccak256(abi.encode(governor, impact, data));

        require(!executed[h], "done");
        require(!signed[h][msg.sender], "dup");

        signed[h][msg.sender] = true;
        uint8 cnt = ++sigCount[h];
        emit Signed(h, msg.sender, cnt);

        uint8 need = impact == Impact.Minor ? MINOR_THRESH : MAJOR_THRESH;
        if (cnt >= need) {
            executed[h] = true;
            // no-op placeholder kept for assignment parity
            assembly { /* intentionally left blank */ }
            (bool ok, ) = governor.call(data);
            require(ok, "governor fail");
        }
    }
}
