# Writing Arbiters (pt 1 - On-chain Arbiters)

Arbiters are smart contracts that implement the `IArbiter` interface to validate whether an obligation (attestation) satisfies specific requirements. They act as on-chain judges that determine if conditions have been met for releasing escrowed assets or fulfilling other blockchain operations.

## Single-transaction arbiters

Single-transaction arbiters perform validation synchronously within a single transaction. They check if an obligation meets the specified demands immediately when called.

### Example 1: String Capitalizer - Synchronous On-chain Computation

This example demonstrates how to write an arbiter that performs synchronous on-chain computations to validate data transformations. It works with a generic data-holding obligation format (`StringObligation`).

**Pattern illustrated**: Validating computational results where both the input (demand) and output (obligation) are stored on-chain, and the validation logic can be executed deterministically.

```solidity
contract StringCapitalizer is IArbiter {
    using ArbiterUtils for Attestation;

    struct DemandData {
        string query;  // Input data
    }

    function checkObligation(
        Attestation memory obligation,
        bytes memory demand,
        bytes32 counteroffer
    ) external view override returns (bool) {
        // Step 1: Validate attestation integrity
        if (!obligation._checkIntrinsic()) return false;

        // Step 2: Check counteroffer reference if provided
        if (counteroffer != bytes32(0) && obligation.refUID != counteroffer) {
            return false;
        }

        // Step 3: Decode both demand and obligation data
        DemandData memory demandData = abi.decode(demand, (DemandData));
        StringObligation.ObligationData memory obligationData =
            abi.decode(obligation.data, (StringObligation.ObligationData));

        // Step 4: Apply validation logic
        return _isCapitalized(demandData.query, obligationData.item);
    }

    function _isCapitalized(
        string memory query,
        string memory result
    ) internal pure returns (bool) {
        // Deterministic computation to validate transformation
        bytes memory queryBytes = bytes(query);
        bytes memory resultBytes = bytes(result);

        if (queryBytes.length != resultBytes.length) return false;

        for (uint256 i = 0; i < queryBytes.length; i++) {
            uint8 queryChar = uint8(queryBytes[i]);
            uint8 resultChar = uint8(resultBytes[i]);

            if (queryChar >= 0x61 && queryChar <= 0x7A) {
                // Lowercase should be capitalized
                if (resultChar != queryChar - 32) return false;
            } else {
                // Non-lowercase should remain unchanged
                if (resultChar != queryChar) return false;
            }
        }

        return true;
    }
}
```

**When to use this pattern**:

- Validating mathematical computations
- Checking data transformations (encoding, formatting, etc.)
- Verifying algorithmic solutions
- Any scenario where validation logic is purely computational

### Example 2: Game Winner - Conditional Escrow for External Attestations

This example demonstrates how to write an arbiter that creates a conditional escrow system for EAS attestations originating from external sources (like a game contract).

**Pattern illustrated**: Validating attestations from trusted external systems, where the arbiter acts as a bridge between existing attestation infrastructure and escrow mechanisms.

```solidity
contract GameWinner is IArbiter {
    using ArbiterUtils for Attestation;

    IEAS public immutable eas;
    bytes32 public immutable GAME_WINNER_SCHEMA;
    address public immutable trustedGameContract;

    struct GameWinnerData {
        bytes32 gameId;
        address winner;
        uint256 timestamp;
        uint256 score;
    }

    struct ClaimDemand {
        bytes32 gameId;
        uint256 minScore;
        uint256 validAfter;
    }

    function checkObligation(
        Attestation memory obligation,
        bytes memory demand,
        bytes32 counteroffer
    ) external view override returns (bool) {
        // Step 1: Validate attestation integrity
        if (!obligation._checkIntrinsic()) return false;

        // Step 2: Verify attestation source and type
        if (obligation.schema != GAME_WINNER_SCHEMA) return false;
        if (obligation.attester != trustedGameContract) return false;

        // Step 3: Check counteroffer reference if provided
        if (counteroffer != bytes32(0) && obligation.refUID != counteroffer) {
            return false;
        }

        // Step 4: Decode and validate against demand criteria
        GameWinnerData memory winnerData =
            abi.decode(obligation.data, (GameWinnerData));
        ClaimDemand memory claimDemand =
            abi.decode(demand, (ClaimDemand));

        // Step 5: Apply conditional logic
        if (winnerData.gameId != claimDemand.gameId) return false;
        if (winnerData.score < claimDemand.minScore) return false;
        if (winnerData.timestamp < claimDemand.validAfter) return false;

        // Step 6: Verify attestation ownership
        if (obligation.recipient != winnerData.winner) return false;

        return true;
    }
}
```

**When to use this pattern**:

- Bridging external attestation systems with escrow contracts
- Creating conditional release mechanisms based on third-party validations
- Implementing trust-based validation where specific attesters are authorized
- Building on top of existing EAS infrastructure

## Common Implementation Pattern

All single-transaction arbiters follow this structure:

1. **Define data structures**: Create structs for demand parameters and expected obligation data
2. **Implement `checkObligation`**: The main validation function that returns a boolean
3. **Validate attestation integrity**: Use `ArbiterUtils` to check expiration and revocation
4. **Verify schema and source** (if needed): Ensure attestations match expected format and origin
5. **Decode data**: Extract information from both obligation and demand
6. **Apply validation logic**: Implement the specific rules for your use case
7. **Return verdict**: Simple pass/fail boolean

The key difference between examples:

- **Computational validation** (StringCapitalizer): Focus on algorithmic verification of data transformations
- **Attestation bridging** (GameWinner): Focus on verifying external attestations and applying conditional logic

## Asynchronous arbiters

Asynchronous arbiters handle validation that cannot be completed in a single transaction, such as time-delayed verification or multi-party consensus.

[example: vote - to be implemented]
