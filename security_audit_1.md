## Neighbor DAO — Solidity Smart-Contract Security Audit  
**Scope (files reviewed)**:  
```
NRT.sol
RepresentativeCouncil.sol
StreakDistributor.sol
NeighborGovernor.sol
NGT.sol
```
**Compiler version**: 0.8.24 
**Audit date**: 28 April 2025

---

### 1. Executive summary

- **Overall risk**: Medium → High
- **Severity breakdown**:
  - Critical: 0
  - High: 1
  - Medium: 3
  - Low: 4
  - Informational: 4
- **Tests run**: Manual review, specification cross‑check, threat modeling
- **Key issue to fix first**: RepresentativeCouncil proposal‑hash weakness (High)

---

### 2. Methodology

- Manual line‑by‑line review of business logic, access control, math, initialization patterns, external‑call surfaces, and DoS vectors.
- Checked for common SWC‑registry issues, re‑entrancy, integer over/underflow (solc ≥ 0.8), front‑running, signature/nonce reuse, and gas griefing.

---

### 3. Detailed findings

**F‑1 (High)** — **RepresentativeCouncil**  
- **Issue**: Proposal hash ignores the `governor` address (`bytes32 h = keccak256(data);`).  
- **Impact**: Council members could execute arbitrary calls (including token transfers) through a malicious contract once the signature threshold is reached.  
- **Recommendation**: Include the governor address (and ideally the `impact` flag) in the hash:
  ```solidity
  h = keccak256(abi.encode(governor, impact, data));
  ```
  Then enforce identical parameters for every signature.

**F‑2 (Medium)** — **RepresentativeCouncil**  
- **Issue**: Cross‑governor denial‑of‑service—`executed[h]` is keyed only by the data hash, so replaying the same proposal on a new governor blocks it permanently.  
- **Impact**: Legitimate proposals for other governor contracts can never execute.  
- **Recommendation**: Key executions by `(governor, hash)` or remove the `executed` entry when a timelock completes.

**F‑3 (Medium)** — **StreakDistributor**  
- **Issue**: Unclaimed‑dust lock‑up—integer division in `share = (q.pool * pts) / totalPoints` leaves a remainder of NRT in the contract.  
- **Impact**: Over time, the unaccounted NRT can accumulate and become inaccessible.  
- **Recommendation**: After final claims or upon expiry, allow the Treasury to sweep remaining balances.

**F‑4 (Medium)** — **NGT**  
- **Issue**: Permanent transfer lock for de‑whitelisted holders—they can only burn tokens via `rageQuit`.  
- **Impact**: Users may lose voting power and funds if removed accidentally.  
- **Recommendation**: Provide a grace period or emergency transfer path through the registrar.

**F‑5 (Low)** — **NRT**  
- **Issue**: Year calculation drifts—`_startOfYear()` and `_rollYear()` assume 365 days exactly, ignoring leap years.  
- **Impact**: Mint budgets drift by ~6 hours per leap-year cycle.  
- **Recommendation**: Use a calendar library (e.g., BokkyPooBah’s DateTime) or document the approximation clearly.

**F‑6 (Low)** — **RepresentativeCouncil**  
- **Issue**: Gas‑heavy linear membership check—`onlyMember` loops through an array on each call.  
- **Impact**: Minor gas DoS if member count grows.  
- **Recommendation**: Switch to a `mapping(address => bool)` or cache member indices.

**F‑7 (Low)** — **StreakDistributor**  
- **Issue**: Missing re‑entrancy guard on `claim`—external `transfer()` after state update is unguarded.  
- **Impact**: Low risk now, but could be exploited with ERC‑777 or custom tokens.  
- **Recommendation**: Add a `nonReentrant` modifier or mark NRT as non‑reentrant.

**F‑8 (Low)** — **NeighborGovernor**  
- **Issue**: Quadratic‑root loop lacks max iteration cap—extremely large `raw` values could cause out‑of‑gas.  
- **Impact**: Edge‑case DoS if token supply ≫ 2²⁵⁶.  
- **Recommendation**: Cap `raw` input or use OpenZeppelin Math’s `sqrt` function (v6.0).

**I‑1 (Informational)** — **All contracts**  
- **Observation**: No explicit proxy initializer checks—potential misuse of OpenZeppelin initializers behind proxies.  
- **Suggestion**: Document non‑upgradeability or call `_disableInitializers()` in constructors.

**I‑2 (Informational)** — **RepresentativeCouncil**  
- **Observation**: Empty Yul block (`assembly {}`) inflates bytecode by ~31 gas.  
- **Suggestion**: Remove or replace with meaningful inline assembly.

**I‑3 (Informational)** — **NGT / NRT**  
- **Observation**: Duplicate `ERC20Burnable` import lines.  
- **Suggestion**: Clean up redundant imports.

**I‑4 (Informational)** — **StreakDistributor**  
- **Observation**: No event emitted for `addPoint`, reducing transparency.  
- **Suggestion**: Emit an event logging `(voter, quarter)`.

---

### 4. Recommendations & best practices

1. **Address F‑1 immediately**—this high‑severity issue is critical.  
2. Build a robust test suite for cap rollover, multi‑sig flows, quadratic vote weights, quarter finalization, and rage‑quit edge cases.  
3. Integrate OpenZeppelin Defender (or similar) for timelock and council monitoring.  
4. Document detailed threat models (assumptions about registrar honesty and council collusion).  
5. Run Slither and Echidna for automated property testing and fuzzing.  
6. Implement ERC‑165 interface IDs for custom contracts.  
7. Formalize your upgrade or immutability strategy; if upgradability is desired, adopt UUPS proxies with disabled initializers:
   ```solidity
   constructor() { _disableInitializers(); }
   ```

---

### 5. Gas & style suggestions (optional)

- Replace `for`‑loop member checks with mapping lookups to save ~20–40 gas per call.  
- Inline storage reads, remove duplicates, and declare constants where possible.  
- Add NatSpec tags (`@dev`, `@custom:oz-upgrades-unsafe-allow`) for clarity.

---

### 6. Conclusion

The Neighbor DAO codebase adheres to OpenZeppelin patterns and is generally clean. Fix the governance‑bypass risk in **F‑1**, then resolve medium findings to achieve a Low‑risk posture before mainnet deployment.


