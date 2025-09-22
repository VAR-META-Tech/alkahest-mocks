# Arbiter Examples

This directory contains example implementations of arbiters that demonstrate different validation patterns for attestations.

## MajorityVoteArbiter

An asynchronous arbiter that validates obligations through majority voting. This arbiter allows multiple authorized voters to vote on whether an attestation satisfies specified requirements.

### Key Features

- **Asynchronous Validation**: Voting happens over multiple transactions, allowing time for voters to review and cast their votes
- **Configurable Quorum**: Each voting session can specify its own quorum requirement
- **Early Completion Detection**: Voting completes as soon as a decision is mathematically determined (either quorum reached or impossible to reach)
- **Vote Tracking**: Full transparency with vote counts and individual voter status tracking

### How It Works

1. **Request Arbitration**: The attester or recipient requests arbitration, specifying:
   - List of authorized voters
   - Quorum (minimum votes needed for approval)
   - Additional data for voter consideration

2. **Voting Process**: Authorized voters cast their votes (yes/no) asynchronously
   - Each voter can only vote once
   - Votes are recorded on-chain with events

3. **Decision Making**: The arbiter approves the obligation when:
   - Yes votes reach the quorum threshold
   - The arbiter rejects when enough no votes make quorum impossible

### Usage Example

```solidity
// Deploy the arbiter
MajorityVoteArbiter arbiter = new MajorityVoteArbiter(eas);

// Set up voting parameters
address[] memory voters = new address[](3);
voters[0] = alice;
voters[1] = bob;
voters[2] = charlie;
uint256 quorum = 2; // Need 2 out of 3 votes to approve

// Encode demand data for the obligation
MajorityVoteArbiter.DemandData memory demandData = MajorityVoteArbiter.DemandData({
    voters: voters,
    quorum: quorum,
    data: abi.encode("Additional context for voters")
});
bytes memory encodedDemand = abi.encode(demandData);

// Request arbitration (by attester or recipient)
arbiter.requestArbitration(obligationUID, voters, quorum);

// Voters cast their votes
arbiter.castVote(obligationUID, true, encodedDemand); // Alice votes yes
arbiter.castVote(obligationUID, true, encodedDemand); // Bob votes yes
// Quorum reached - obligation is approved

// Check if obligation passes
bool approved = arbiter.checkObligation(obligation, encodedDemand, bytes32(0));
```

### Alternative Implementation Approach

This voting functionality could also be implemented as a separate voting contract that aggregates votes and then submits the final result to `TrustedOracleArbiter`. This approach would:

- Separate voting logic from arbitration logic
- Allow reuse of existing TrustedOracleArbiter infrastructure
- Enable different voting mechanisms (ranked choice, weighted voting, etc.) without creating new arbiters

Example alternative architecture:
```solidity
// Voting contract aggregates votes
VotingAggregator votingContract = new VotingAggregator();
votingContract.startVoting(obligationUID, voters, quorum);
// ... voting happens ...
votingContract.finalizeVoting(obligationUID);

// Voting contract acts as the trusted oracle for TrustedOracleArbiter
TrustedOracleArbiter arbiter = new TrustedOracleArbiter(eas);
arbiter.arbitrate(obligationUID, votingResult); // Called by voting contract
```

## Other Examples

### StringCapitalizer
Synchronous arbiter that validates string transformation operations. Demonstrates on-chain computational validation.

### GameWinner
Synchronous arbiter that validates game winner attestations from trusted game contracts. Demonstrates bridging external attestation systems.

### OptimisticStringValidator
Demonstrates optimistic validation patterns where attestations are assumed valid unless challenged within a time window.
