// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Attestation} from "@eas/Common.sol";
import {IEAS, AttestationRequest, AttestationRequestData, RevocationRequest, RevocationRequestData} from "@eas/IEAS.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";
import {BaseObligation} from "../BaseObligation.sol";
import {IArbiter} from "../IArbiter.sol";
import {ArbiterUtils} from "../ArbiterUtils.sol";

contract AttestationEscrowObligation is BaseObligation, IArbiter {
    using ArbiterUtils for Attestation;

    struct ObligationData {
        address arbiter;
        bytes demand;
        AttestationRequest attestation;
    }

    event EscrowMade(bytes32 indexed payment, address indexed buyer);
    event EscrowClaimed(
        bytes32 indexed payment,
        bytes32 indexed fulfillment,
        address indexed fulfiller
    );

    error InvalidEscrowAttestation();
    error InvalidFulfillment();
    error UnauthorizedCall();

    constructor(
        IEAS _eas,
        ISchemaRegistry _schemaRegistry
    )
        BaseObligation(
            _eas,
            _schemaRegistry,
            "address arbiter, bytes demand, tuple(bytes32 schema, tuple(address recipient, uint64 expirationTime, bool revocable, bytes32 refUID, bytes data, uint256 value) data) attestation",
            true
        )
    {}

    function doObligationFor(
        ObligationData calldata data,
        uint64 expirationTime,
        address recipient
    ) public returns (bytes32 uid_) {
        uid_ = eas.attest(
            AttestationRequest({
                schema: ATTESTATION_SCHEMA,
                data: AttestationRequestData({
                    recipient: recipient,
                    expirationTime: expirationTime,
                    revocable: true,
                    refUID: bytes32(0),
                    data: abi.encode(data),
                    value: 0
                })
            })
        );
        emit EscrowMade(uid_, recipient);
    }

    function doObligation(
        ObligationData calldata data,
        uint64 expirationTime
    ) public returns (bytes32 uid_) {
        return doObligationFor(data, expirationTime, msg.sender);
    }

    error AttestationNotFound(bytes32 attestationId);
    error RevocationFailed(bytes32 attestationId);
    error AttestationCreationFailed();

    function collectEscrow(
        bytes32 _escrow,
        bytes32 _fulfillment
    ) public returns (bytes32) {
        Attestation memory escrow;
        Attestation memory fulfillment;

        try eas.getAttestation(_escrow) returns (Attestation memory escrow_) {
            escrow = escrow_;
        } catch {
            revert AttestationNotFound(_escrow);
        }

        try eas.getAttestation(_fulfillment) returns (
            Attestation memory fulfillment_
        ) {
            fulfillment = fulfillment_;
        } catch {
            revert AttestationNotFound(_fulfillment);
        }

        if (!escrow._checkIntrinsic()) revert InvalidEscrowAttestation();

        ObligationData memory escrowData = abi.decode(
            escrow.data,
            (ObligationData)
        );

        if (
            !IArbiter(escrowData.arbiter).checkObligation(
                fulfillment,
                escrowData.demand,
                escrow.uid
            )
        ) revert InvalidFulfillment();

        try
            eas.revoke(
                RevocationRequest({
                    schema: ATTESTATION_SCHEMA,
                    data: RevocationRequestData({uid: _escrow, value: 0})
                })
            )
        {} catch {
            revert RevocationFailed(_escrow);
        }

        bytes32 attestationUid;
        try eas.attest(escrowData.attestation) returns (bytes32 uid) {
            attestationUid = uid;
        } catch {
            revert AttestationCreationFailed();
        }

        emit EscrowClaimed(_escrow, _fulfillment, fulfillment.recipient);
        return attestationUid;
    }

    function checkObligation(
        Attestation memory obligation,
        bytes memory demand,
        bytes32 /* counteroffer */
    ) public view override returns (bool) {
        if (!obligation._checkIntrinsic(ATTESTATION_SCHEMA)) return false;

        ObligationData memory escrow = abi.decode(
            obligation.data,
            (ObligationData)
        );
        ObligationData memory demandData = abi.decode(demand, (ObligationData));

        return
            keccak256(abi.encode(escrow.attestation)) ==
            keccak256(abi.encode(demandData.attestation)) &&
            escrow.arbiter == demandData.arbiter &&
            keccak256(escrow.demand) == keccak256(demandData.demand);
    }

    function getObligationData(
        bytes32 uid
    ) public view returns (ObligationData memory) {
        Attestation memory attestation = eas.getAttestation(uid);
        if (attestation.schema != ATTESTATION_SCHEMA)
            revert InvalidEscrowAttestation();
        return abi.decode(attestation.data, (ObligationData));
    }

    function decodeObligationData(
        bytes calldata data
    ) public pure returns (ObligationData memory) {
        return abi.decode(data, (ObligationData));
    }
}
