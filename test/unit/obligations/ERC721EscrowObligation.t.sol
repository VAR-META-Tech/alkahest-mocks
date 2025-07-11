// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ERC721EscrowObligation} from "@src/obligations/ERC721EscrowObligation.sol";
import {StringObligation} from "@src/obligations/StringObligation.sol";
import {IArbiter} from "@src/IArbiter.sol";
import {MockArbiter} from "./MockArbiter.sol";
import {IEAS, Attestation, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData} from "@eas/IEAS.sol";
import {ISchemaRegistry, SchemaRecord} from "@eas/ISchemaRegistry.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {EASDeployer} from "@test/utils/EASDeployer.sol";

// Mock ERC721 token for testing
contract MockERC721 is ERC721 {
    uint256 private _nextTokenId;

    constructor() ERC721("Mock ERC721", "MERC721") {}

    function mint(address to) public returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _mint(to, tokenId);
        return tokenId;
    }
}

contract ERC721EscrowObligationTest is Test {
    ERC721EscrowObligation public escrowObligation;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;
    MockERC721 public token;
    MockArbiter public mockArbiter;
    MockArbiter public rejectingArbiter;

    address internal buyer;
    address internal seller;
    uint256 internal tokenId;
    uint64 constant EXPIRATION_TIME = 365 days;

    function setUp() public {
        EASDeployer easDeployer = new EASDeployer();
        (eas, schemaRegistry) = easDeployer.deployEAS();

        escrowObligation = new ERC721EscrowObligation(eas, schemaRegistry);
        token = new MockERC721();
        mockArbiter = new MockArbiter(true);
        rejectingArbiter = new MockArbiter(false);

        buyer = makeAddr("buyer");
        seller = makeAddr("seller");

        // Mint a token for the buyer
        vm.prank(address(this));
        tokenId = token.mint(buyer);
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
            "address arbiter, bytes demand, address token, uint256 tokenId",
            "Schema string should match"
        );
    }

    function testMakeStatement() public {
        // Approve ERC721 transfer first
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);

        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: demand
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
        assertEq(attestation.recipient, buyer, "Recipient should be the buyer");

        // Verify token transfer to escrow
        assertEq(
            token.ownerOf(tokenId),
            address(escrowObligation),
            "Escrow should hold the token"
        );
    }

    function testDoObligationFor() public {
        // Approve ERC721 transfer first
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);
        vm.stopPrank();

        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: demand
            });

        address recipient = makeAddr("recipient");
        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);

        vm.prank(address(this));
        bytes32 uid = escrowObligation.doObligationFor(
            data,
            expiration,
            buyer,
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

        // Verify token transfer to escrow
        assertEq(
            token.ownerOf(tokenId),
            address(escrowObligation),
            "Escrow should hold the token"
        );
    }

    function testCollectEscrow() public {
        // Setup: create an escrow
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);

        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: demand
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        bytes32 paymentUid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        // Create a fulfillment attestation using a StringObligation
        StringObligation stringObligation = new StringObligation(
            eas,
            schemaRegistry
        );

        vm.prank(seller);
        bytes32 fulfillmentUid = stringObligation.doObligation(
            StringObligation.ObligationData({item: "fulfillment data"}),
            bytes32(0)
        );

        // Collect payment
        vm.prank(seller);
        bool success = escrowObligation.collectEscrow(
            paymentUid,
            fulfillmentUid
        );

        assertTrue(success, "Payment collection should succeed");

        // Verify token transfer to seller
        assertEq(
            token.ownerOf(tokenId),
            seller,
            "Seller should have received the token"
        );
    }

    function testCollectEscrowWithRejectedFulfillment() public {
        // Setup: create an escrow with rejecting arbiter
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);

        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(rejectingArbiter),
                demand: demand
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);
        bytes32 paymentUid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        // Create a fulfillment attestation using a StringObligation
        StringObligation stringObligation = new StringObligation(
            eas,
            schemaRegistry
        );

        vm.prank(seller);
        bytes32 fulfillmentUid = stringObligation.doObligation(
            StringObligation.ObligationData({item: "fulfillment data"}),
            bytes32(0)
        );

        // Try to collect payment, should revert with InvalidFulfillment
        vm.prank(seller);
        vm.expectRevert(ERC721EscrowObligation.InvalidFulfillment.selector);
        escrowObligation.collectEscrow(paymentUid, fulfillmentUid);
    }

    function testReclaimExpired() public {
        // Setup: create an escrow
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);

        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: demand
            });

        uint64 expiration = uint64(block.timestamp + 100);
        bytes32 paymentUid = escrowObligation.doObligation(data, expiration);
        vm.stopPrank();

        // Attempt to collect before expiration (should fail)
        vm.prank(buyer);
        vm.expectRevert(ERC721EscrowObligation.UnauthorizedCall.selector);
        escrowObligation.reclaimExpired(paymentUid);

        // Fast forward past expiration time
        vm.warp(block.timestamp + 200);

        // Collect expired funds
        vm.prank(buyer);
        bool success = escrowObligation.reclaimExpired(paymentUid);

        assertTrue(success, "Expired token collection should succeed");

        // Verify token transfer back to buyer
        assertEq(
            token.ownerOf(tokenId),
            buyer,
            "Buyer should have received the token back"
        );
    }

    function testCheckObligation() public {
        // Create obligation data
        ERC721EscrowObligation.ObligationData
            memory paymentData = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        // Use the obligation contract to create a valid attestation
        vm.startPrank(buyer);
        token.approve(address(escrowObligation), tokenId);
        bytes32 attestationId = escrowObligation.doObligation(
            paymentData,
            uint64(block.timestamp + EXPIRATION_TIME)
        );
        vm.stopPrank();

        Attestation memory attestation = eas.getAttestation(attestationId);

        // Test exact match
        ERC721EscrowObligation.ObligationData
            memory exactDemand = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        bool exactMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(exactDemand),
            bytes32(0)
        );
        assertTrue(exactMatch, "Should match exact demand");

        // Test different token ID (should fail)
        uint256 differentTokenId = 999;
        ERC721EscrowObligation.ObligationData
            memory differentTokenIdDemand = ERC721EscrowObligation
                .ObligationData({
                    token: address(token),
                    tokenId: differentTokenId,
                    arbiter: address(mockArbiter),
                    demand: abi.encode("specific demand")
                });

        bool differentTokenIdMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(differentTokenIdDemand),
            bytes32(0)
        );
        assertFalse(
            differentTokenIdMatch,
            "Should not match different token ID demand"
        );

        // Test different token (should fail)
        MockERC721 differentToken = new MockERC721();
        ERC721EscrowObligation.ObligationData
            memory differentTokenDemand = ERC721EscrowObligation.ObligationData({
                token: address(differentToken),
                tokenId: tokenId,
                arbiter: address(mockArbiter),
                demand: abi.encode("specific demand")
            });

        bool differentTokenMatch = escrowObligation.checkObligation(
            attestation,
            abi.encode(differentTokenDemand),
            bytes32(0)
        );
        assertFalse(
            differentTokenMatch,
            "Should not match different token demand"
        );

        // Test different arbiter (should fail)
        ERC721EscrowObligation.ObligationData
            memory differentArbiterDemand = ERC721EscrowObligation
                .ObligationData({
                    token: address(token),
                    tokenId: tokenId,
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
            "Should not match different arbiter demand"
        );

        // Test different demand (should fail)
        ERC721EscrowObligation.ObligationData
            memory differentDemandData = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: tokenId,
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

    function testTransferFailureReverts() public {
        // Mint a token for a different address that won't approve the transfer
        address otherOwner = makeAddr("otherOwner");
        uint256 otherTokenId = token.mint(otherOwner);

        // Try to create escrow with a token that hasn't been approved for transfer
        bytes memory demand = abi.encode("test demand");
        ERC721EscrowObligation.ObligationData
            memory data = ERC721EscrowObligation.ObligationData({
                token: address(token),
                tokenId: otherTokenId,
                arbiter: address(mockArbiter),
                demand: demand
            });

        uint64 expiration = uint64(block.timestamp + EXPIRATION_TIME);

        // Should revert with our custom ERC721TransferFailed error
        vm.expectRevert(
            abi.encodeWithSelector(
                ERC721EscrowObligation.ERC721TransferFailed.selector,
                address(token),
                otherOwner,
                address(escrowObligation),
                otherTokenId
            )
        );
        escrowObligation.doObligationFor(
            data,
            expiration,
            otherOwner,
            otherOwner
        );
    }
}
