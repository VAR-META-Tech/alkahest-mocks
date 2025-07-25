// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {AttestationEscrowObligation} from "@src/obligations/AttestationEscrowObligation.sol";
import {StringObligation} from "@src/obligations/StringObligation.sol";
import {IArbiter} from "@src/IArbiter.sol";
import {MockArbiter} from "./MockArbiter.sol";
import {ArbiterUtils} from "@src/ArbiterUtils.sol";
import {IEAS, Attestation, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData} from "@eas/IEAS.sol";
import {ISchemaRegistry, SchemaRecord} from "@eas/ISchemaRegistry.sol";
import {ISchemaResolver} from "@eas/resolver/ISchemaResolver.sol";
import {EASDeployer} from "@test/utils/EASDeployer.sol";

contract AttestationEscrowObligationTest is Test {
    AttestationEscrowObligation public escrowObligation;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;
    MockArbiter public mockArbiter;
    MockArbiter public rejectingArbiter;

    address internal requester;
    address internal attester;
    address internal recipient;

    // Test schema ID (will be registered during setup)
    bytes32 private testSchemaId;

    uint64 constant EXPIRATION_TIME = 365 days;

    function setUp() public {
        // Set block and time to something reasonable, or expiration won't work
        vm.warp(10 << 12);
        vm.roll(10 << 4);

        EASDeployer easDeployer = new EASDeployer();
        (eas, schemaRegistry) = easDeployer.deployEAS();

        escrowObligation = new AttestationEscrowObligation(eas, schemaRegistry);
        mockArbiter = new MockArbiter(true);
        rejectingArbiter = new MockArbiter(false);

        requester = makeAddr("requester");
        attester = makeAddr("attester");
        recipient = makeAddr("recipient");

        // Register a test schema for our tests
        vm.prank(address(this));
        testSchemaId = schemaRegistry.register(
            "string testData",
            ISchemaResolver(address(0)),
            true // Make schema revocable
        );
    }

    function testConstructor() public view {
        // Verify contract was initialized correctly
        bytes32 schemaId = escrowObligation.ATTESTATION_SCHEMA();
        assertNotEq(schemaId, bytes32(0), "Schema should be registered");

        // Verify schema details
        SchemaRecord memory schema = escrowObligation.getSchema();
        assertEq(schema.uid, schemaId, "Schema UID should match");
        assertEq(
            schema.schema,
            "address arbiter, bytes demand, tuple(bytes32 schema, tuple(address recipient, uint64 expirationTime, bool revocable, bytes32 refUID, bytes data, uint256 value) data) attestation",
            "Schema string should match"
        );
    }

    function testMakeStatement() public {
        vm.startPrank(requester);

        // Create the attestation request
        AttestationRequest
            memory attestationRequest = createTestAttestationRequest();

        // Create the obligation data
        AttestationEscrowObligation.ObligationData
            memory data = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("test demand")
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        bytes32 uid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        // Verify attestation exists
        assertNotEq(uid, bytes32(0), "Attestation should be created");

        // Verify attestation details
        Attestation memory attestation = escrowObligation.getObligation(uid);
        assertEq(
            attestation.schema,
            escrowObligation.ATTESTATION_SCHEMA(),
            "Schema should match"
        );
        assertEq(
            attestation.recipient,
            requester,
            "Recipient should be the requester"
        );
    }

    function testDoObligationFor() public {
        // Create the attestation request
        AttestationRequest
            memory attestationRequest = createTestAttestationRequest();

        // Create the obligation data
        AttestationEscrowObligation.ObligationData
            memory data = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("test demand")
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);

        vm.prank(address(this));
        bytes32 uid = escrowObligation.doObligationFor(
            data,
            expiration,
            recipient
        );

        // Verify attestation exists
        assertNotEq(uid, bytes32(0), "Attestation should be created");

        // Verify attestation details
        Attestation memory attestation = escrowObligation.getObligation(uid);
        assertEq(
            attestation.schema,
            escrowObligation.ATTESTATION_SCHEMA(),
            "Schema should match"
        );
        assertEq(
            attestation.recipient,
            recipient,
            "Recipient should be the specified recipient"
        );
    }

    // Helper function to create a fulfillment and escrow attestation
    function createFulfillmentAndEscrow(
        address arbiterAddr
    ) internal returns (bytes32 fulfillmentUid, bytes32 escrowUid) {
        // Create a fulfillment attestation data
        AttestationRequest
            memory fulfillmentRequest = createTestAttestationRequest();
        fulfillmentRequest.data.data = abi.encode("fulfillment data");
        fulfillmentRequest.data.recipient = attester;

        AttestationEscrowObligation.ObligationData
            memory fulfillmentData = AttestationEscrowObligation.ObligationData({
                attestation: fulfillmentRequest,
                arbiter: arbiterAddr,
                demand: abi.encode("fulfillment demand")
            });

        uint64 fulfillmentExpiration = uint64(
            block.timestamp + EXPIRATION_TIME
        );

        // Create the fulfillment attestation
        vm.startPrank(attester);
        fulfillmentUid = escrowObligation.doObligation(
            fulfillmentData,
            fulfillmentExpiration
        );
        vm.stopPrank();

        // Create the escrow attestation
        vm.startPrank(requester);

        AttestationRequest
            memory attestationRequest = createTestAttestationRequest();

        AttestationEscrowObligation.ObligationData
            memory data = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: arbiterAddr,
                demand: abi.encode("test demand")
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        escrowUid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        return (fulfillmentUid, escrowUid);
    }

    function testCollectEscrow_Successful() public {
        // For this test to pass, we need to make the mockArbiter's checkObligation function return true
        // First setup the test
        bytes32 fulfillmentUid;
        bytes32 escrowUid;
        (fulfillmentUid, escrowUid) = createFulfillmentAndEscrow(
            address(mockArbiter)
        );

        // Make sure arbiter accepts the fulfillment
        mockArbiter.setShouldAccept(true);

        // Collect payment
        vm.prank(attester);
        bytes32 attestationUid = escrowObligation.collectEscrow(
            escrowUid,
            fulfillmentUid
        );

        // Verify the payment attestation was created
        assertNotEq(
            attestationUid,
            bytes32(0),
            "Payment attestation should be created"
        );

        // Get and verify the original escrow attestation is revoked
        Attestation memory escrow = eas.getAttestation(escrowUid);
        assertGt(
            escrow.revocationTime,
            0,
            "Escrow attestation should be revoked"
        );
    }

    // Test payment collection with rejected fulfillment
    function test_RevertWhen_FulfillmentRejected() public {
        // Create StringObligation for fulfillment
        StringObligation stringObligation = new StringObligation(
            eas,
            schemaRegistry
        );

        // Create an escrow attestation with rejecting arbiter
        vm.startPrank(requester);
        AttestationRequest
            memory attestationRequest = createTestAttestationRequest();

        AttestationEscrowObligation.ObligationData
            memory data = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(rejectingArbiter),
                demand: abi.encode("test demand")
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        bytes32 escrowUid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        // Create a fulfillment attestation
        vm.startPrank(attester);
        bytes32 fulfillmentUid = stringObligation.doObligation(
            StringObligation.ObligationData({item: "fulfillment data"}),
            bytes32(0)
        );

        // Try to collect payment, should revert with InvalidFulfillment
        vm.expectRevert(
            AttestationEscrowObligation.InvalidFulfillment.selector
        );
        escrowObligation.collectEscrow(escrowUid, fulfillmentUid);
        vm.stopPrank();
    }

    // Helper function to create a valid attestation for testing
    function createValidAttestation()
        internal
        returns (Attestation memory, AttestationRequest memory)
    {
        // Create obligation data through the contract to ensure we have a valid attestation
        AttestationRequest
            memory attestationRequest = createTestAttestationRequest();

        AttestationEscrowObligation.ObligationData
            memory escrowData = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        // Create the obligation through the contract's function
        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        vm.prank(requester);
        bytes32 obligationId = escrowObligation.doObligation(
            escrowData,
            expiration
        );

        // Get the attestation
        Attestation memory attestation = escrowObligation.getObligation(
            obligationId
        );

        return (attestation, attestationRequest);
    }

    // Test case for exact match
    function testCheckObligation_ExactMatch() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest // Used to create exactDemand
        ) = createValidAttestation();

        // Test exact match
        AttestationEscrowObligation.ObligationData
            memory exactDemand = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        bool exactMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(exactDemand),
            bytes32(0)
        );
        assertTrue(exactMatch, "Should match exact demand");
    }

    // Test case for expired attestation
    function test_RevertWhen_AttestationExpired() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest // Used to create exactDemand
        ) = createValidAttestation();

        // Create demand to match against
        AttestationEscrowObligation.ObligationData
            memory exactDemand = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        // Create expired attestation
        Attestation memory expiredAttestation = attestation;
        expiredAttestation.expirationTime = uint64(block.timestamp - 1); // Expired

        vm.expectRevert(ArbiterUtils.DeadlineExpired.selector);
        escrowObligation.checkObligation(
            expiredAttestation,
            abi.encode(exactDemand),
            bytes32(0)
        );
    }

    // Test case for wrong schema
    function test_RevertWhen_SchemaInvalid() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest // Used to create exactDemand
        ) = createValidAttestation();

        // Create demand to match against
        AttestationEscrowObligation.ObligationData
            memory exactDemand = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        // Create wrong schema attestation
        Attestation memory wrongSchemaAttestation = attestation;
        wrongSchemaAttestation.schema = bytes32(uint256(1)); // Different schema

        vm.expectRevert(ArbiterUtils.InvalidSchema.selector);
        escrowObligation.checkObligation(
            wrongSchemaAttestation,
            abi.encode(exactDemand),
            bytes32(0)
        );
    }

    // Test case for revoked attestation
    function test_RevertWhen_AttestationRevoked() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest // Used to create exactDemand
        ) = createValidAttestation();

        // Create demand to match against
        AttestationEscrowObligation.ObligationData
            memory exactDemand = AttestationEscrowObligation.ObligationData({
                attestation: attestationRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        // Create revoked attestation
        Attestation memory revokedAttestation = attestation;
        revokedAttestation.revocationTime = uint64(block.timestamp - 1); // Revoked

        vm.expectRevert(ArbiterUtils.AttestationRevoked.selector);
        escrowObligation.checkObligation(
            revokedAttestation,
            abi.encode(exactDemand),
            bytes32(0)
        );
    }

    // Test case for different attestation request
    function testCheckObligation_DifferentAttestationRequest() public {
        // Only using the attestation from the return value, not the attestationRequest
        (
            Attestation memory attestation,
            /* AttestationRequest memory attestationRequest */
        ) = createValidAttestation();

        // Test different attestation request (should not match)
        AttestationRequest
            memory differentAttestationRequest = createTestAttestationRequest();
        differentAttestationRequest.data.data = abi.encode("different data");

        AttestationEscrowObligation.ObligationData
            memory differentAttestationDemand = AttestationEscrowObligation
                .ObligationData({
                    attestation: differentAttestationRequest,
                    arbiter: address(mockArbiter),
                    demand: abi.encode("specific demand")
                });

        bool differentAttestationMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(differentAttestationDemand),
            bytes32(0)
        );
        assertFalse(
            differentAttestationMatch,
            "Should not match different attestation request"
        );
    }

    // Test case for different arbiter
    function testCheckObligation_DifferentArbiter() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest
        ) = createValidAttestation();

        // Test different arbiter (should not match)
        AttestationEscrowObligation.ObligationData
            memory differentArbiterDemand = AttestationEscrowObligation
                .ObligationData({
                    attestation: attestationRequest,
                    arbiter: address(rejectingArbiter),
                    demand: abi.encode("specific demand")
                });

        bool differentArbiterMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(differentArbiterDemand),
            bytes32(0)
        );
        assertFalse(
            differentArbiterMatch,
            "Should not match different arbiter"
        );
    }

    // Test case for different demand
    function testCheckObligation_DifferentDemand() public {
        (
            Attestation memory attestation,
            AttestationRequest memory attestationRequest
        ) = createValidAttestation();

        // Test different demand (should not match)
        AttestationEscrowObligation.ObligationData
            memory differentDemandData = AttestationEscrowObligation
                .ObligationData({
                    attestation: attestationRequest,
                    arbiter: address(mockArbiter),
                    demand: abi.encode("different demand")
                });

        bool differentDemandMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(differentDemandData),
            bytes32(0)
        );
        assertFalse(differentDemandMatch, "Should not match different demand");
    }

    function test_RevertWhen_EscrowAttestationInvalid() public {
        // Create a mock invalid attestation ID
        bytes32 invalidAttestationId = bytes32(uint256(1));

        // Create a valid fulfillment attestation
        AttestationRequest
            memory fulfillmentRequest = createTestAttestationRequest();
        fulfillmentRequest.data.data = abi.encode("fulfillment data");
        fulfillmentRequest.data.recipient = attester;

        AttestationEscrowObligation.ObligationData
            memory fulfillmentData = AttestationEscrowObligation.ObligationData({
                attestation: fulfillmentRequest,
                arbiter: address(mockArbiter),
                demand: abi.encode("fulfillment demand")
            });

        uint64 fulfillmentExpiration = uint64(
            block.timestamp + EXPIRATION_TIME
        );

        vm.startPrank(attester);
        bytes32 fulfillmentUid = escrowObligation.doObligation(
            fulfillmentData,
            fulfillmentExpiration
        );
        vm.stopPrank();

        // Try to collect payment with an invalid escrow attestation ID
        vm.startPrank(attester);
        // The test should expect a generic revert when the attestation ID is not found
        // This is because the EAS contract is likely returning a generic revert when the attestation doesn't exist
        vm.expectRevert();
        escrowObligation.collectEscrow(invalidAttestationId, fulfillmentUid);
        vm.stopPrank();
    }

    // Helper function to create a test attestation request
    function createTestAttestationRequest()
        internal
        view
        returns (AttestationRequest memory)
    {
        AttestationRequestData memory requestData = AttestationRequestData({
            recipient: recipient,
            expirationTime: 0,
            revocable: true,
            refUID: bytes32(0),
            data: abi.encode("test attestation data"),
            value: 0
        });

        return AttestationRequest({schema: testSchemaId, data: requestData});
    }
}
