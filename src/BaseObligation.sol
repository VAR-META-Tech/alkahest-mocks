// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IArbiter} from "./IArbiter.sol";
import {IEAS} from "@eas/IEAS.sol";
import {ISchemaRegistry, SchemaRecord} from "@eas/ISchemaRegistry.sol";
import {SchemaResolver} from "@eas/resolver/SchemaResolver.sol";
import {Attestation} from "@eas/Common.sol";

abstract contract BaseObligation is SchemaResolver {
    ISchemaRegistry internal immutable schemaRegistry;
    IEAS internal immutable eas;
    bytes32 public immutable ATTESTATION_SCHEMA;

    error NotFromObligation();

    constructor(
        IEAS _eas,
        ISchemaRegistry _schemaRegistry,
        string memory schema,
        bool revocable
    ) SchemaResolver(_eas) {
        eas = _eas;
        schemaRegistry = _schemaRegistry;
        ATTESTATION_SCHEMA = schemaRegistry.register(schema, this, revocable);
    }

    function onAttest(
        Attestation calldata attestation,
        uint256 /* value */
    ) internal view override returns (bool) {
        // only obligation contract can attest
        return attestation.attester == address(this);
    }

    function onRevoke(
        Attestation calldata attestation,
        uint256 /* value */
    ) internal view override returns (bool) {
        // only obligation contract can revoke
        return attestation.attester == address(this);
    }

    function getObligation(
        bytes32 uid
    ) external view returns (Attestation memory) {
        Attestation memory attestation = eas.getAttestation(uid);
        if (attestation.schema != ATTESTATION_SCHEMA) revert NotFromObligation();
        return attestation;
    }

    function getSchema() external view returns (SchemaRecord memory) {
        return schemaRegistry.getSchema(ATTESTATION_SCHEMA);
    }
}
