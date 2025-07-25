// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20BarterUtils} from "./ERC20BarterUtils.sol";
import {IEAS} from "@eas/IEAS.sol";
import {Attestation} from "@eas/Common.sol";
import {ERC20EscrowObligation} from "../obligations/ERC20EscrowObligation.sol";
import {ERC20PaymentObligation} from "../obligations/ERC20PaymentObligation.sol";
import {ERC721EscrowObligation} from "../obligations/ERC721EscrowObligation.sol";
import {ERC721PaymentObligation} from "../obligations/ERC721PaymentObligation.sol";
import {ERC1155EscrowObligation} from "../obligations/ERC1155EscrowObligation.sol";
import {ERC1155PaymentObligation} from "../obligations/ERC1155PaymentObligation.sol";
import {TokenBundleEscrowObligation} from "../obligations/TokenBundleEscrowObligation.sol";
import {TokenBundlePaymentObligation} from "../obligations/TokenBundlePaymentObligation.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract ERC20BarterCrossToken is ERC20BarterUtils {
    ERC721EscrowObligation internal erc721Escrow;
    ERC721PaymentObligation internal erc721Payment;
    ERC1155EscrowObligation internal erc1155Escrow;
    ERC1155PaymentObligation internal erc1155Payment;
    TokenBundleEscrowObligation internal bundleEscrow;
    TokenBundlePaymentObligation internal bundlePayment;

    error PermitFailed(address token, string reason);
    error AttestationNotFound(bytes32 attestationId);

    constructor(
        IEAS _eas,
        ERC20EscrowObligation _erc20Escrow,
        ERC20PaymentObligation _erc20Payment,
        ERC721EscrowObligation _erc721Escrow,
        ERC721PaymentObligation _erc721Payment,
        ERC1155EscrowObligation _erc1155Escrow,
        ERC1155PaymentObligation _erc1155Payment,
        TokenBundleEscrowObligation _bundleEscrow,
        TokenBundlePaymentObligation _bundlePayment
    ) ERC20BarterUtils(_eas, _erc20Escrow, _erc20Payment) {
        erc721Escrow = _erc721Escrow;
        erc721Payment = _erc721Payment;
        erc1155Escrow = _erc1155Escrow;
        erc1155Payment = _erc1155Payment;
        bundleEscrow = _bundleEscrow;
        bundlePayment = _bundlePayment;
    }

    // Internal functions
    function _permitPayment(
        ERC20PaymentObligation.ObligationData memory demand,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal {
        IERC20Permit askTokenC = IERC20Permit(demand.token);

        try
            askTokenC.permit(
                msg.sender,
                address(erc20Payment),
                demand.amount,
                deadline,
                v,
                r,
                s
            )
        {} catch Error(string memory reason) {
            revert PermitFailed(demand.token, reason);
        } catch {
            revert PermitFailed(demand.token, "Unknown error");
        }
    }

    function _buyErc721WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint64 expiration
    ) internal returns (bytes32) {
        return
            erc20Escrow.doObligationFor(
                ERC20EscrowObligation.ObligationData({
                    token: bidToken,
                    amount: bidAmount,
                    arbiter: address(erc721Payment),
                    demand: abi.encode(
                        ERC721PaymentObligation.ObligationData({
                            token: askToken,
                            tokenId: askId,
                            payee: msg.sender
                        })
                    )
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function _buyErc1155WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint256 askAmount,
        uint64 expiration
    ) internal returns (bytes32) {
        return
            erc20Escrow.doObligationFor(
                ERC20EscrowObligation.ObligationData({
                    token: bidToken,
                    amount: bidAmount,
                    arbiter: address(erc1155Payment),
                    demand: abi.encode(
                        ERC1155PaymentObligation.ObligationData({
                            token: askToken,
                            tokenId: askId,
                            amount: askAmount,
                            payee: msg.sender
                        })
                    )
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function _buyBundleWithErc20(
        address bidToken,
        uint256 bidAmount,
        TokenBundlePaymentObligation.ObligationData memory askData,
        uint64 expiration
    ) internal returns (bytes32) {
        return
            erc20Escrow.doObligationFor(
                ERC20EscrowObligation.ObligationData({
                    token: bidToken,
                    amount: bidAmount,
                    arbiter: address(bundlePayment),
                    demand: abi.encode(askData)
                }),
                expiration,
                msg.sender,
                msg.sender
            );
    }

    function _payErc20ForErc721(
        bytes32 buyAttestation,
        ERC20PaymentObligation.ObligationData memory demand
    ) internal returns (bytes32) {
        bytes32 sellAttestation = erc20Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!erc721Escrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    function _payErc20ForErc1155(
        bytes32 buyAttestation,
        ERC20PaymentObligation.ObligationData memory demand
    ) internal returns (bytes32) {
        bytes32 sellAttestation = erc20Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!erc1155Escrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    function _payErc20ForBundle(
        bytes32 buyAttestation,
        ERC20PaymentObligation.ObligationData memory demand
    ) internal returns (bytes32) {
        bytes32 sellAttestation = erc20Payment.doObligationFor(
            demand,
            msg.sender,
            msg.sender
        );

        if (!bundleEscrow.collectEscrow(buyAttestation, sellAttestation)) {
            revert CouldntCollectEscrow();
        }

        return sellAttestation;
    }

    // External functions for ERC721
    function buyErc721WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint64 expiration
    ) external returns (bytes32) {
        return
            _buyErc721WithErc20(
                bidToken,
                bidAmount,
                askToken,
                askId,
                expiration
            );
    }

    function permitAndBuyErc721WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint64 expiration,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        IERC20Permit bidTokenC = IERC20Permit(bidToken);
        try
            bidTokenC.permit(
                msg.sender,
                address(erc20Escrow),
                bidAmount,
                deadline,
                v,
                r,
                s
            )
        {} catch Error(string memory reason) {
            revert PermitFailed(bidToken, reason);
        } catch {
            revert PermitFailed(bidToken, "Unknown error");
        }

        return
            _buyErc721WithErc20(
                bidToken,
                bidAmount,
                askToken,
                askId,
                expiration
            );
    }

    // External functions for ERC1155
    function buyErc1155WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint256 askAmount,
        uint64 expiration
    ) external returns (bytes32) {
        return
            _buyErc1155WithErc20(
                bidToken,
                bidAmount,
                askToken,
                askId,
                askAmount,
                expiration
            );
    }

    function permitAndBuyErc1155WithErc20(
        address bidToken,
        uint256 bidAmount,
        address askToken,
        uint256 askId,
        uint256 askAmount,
        uint64 expiration,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        IERC20Permit bidTokenC = IERC20Permit(bidToken);
        try
            bidTokenC.permit(
                msg.sender,
                address(erc20Escrow),
                bidAmount,
                deadline,
                v,
                r,
                s
            )
        {} catch Error(string memory reason) {
            revert PermitFailed(bidToken, reason);
        } catch {
            revert PermitFailed(bidToken, "Unknown error");
        }

        return
            _buyErc1155WithErc20(
                bidToken,
                bidAmount,
                askToken,
                askId,
                askAmount,
                expiration
            );
    }

    // External functions for Token Bundle
    function buyBundleWithErc20(
        address bidToken,
        uint256 bidAmount,
        TokenBundlePaymentObligation.ObligationData calldata askData,
        uint64 expiration
    ) external returns (bytes32) {
        return _buyBundleWithErc20(bidToken, bidAmount, askData, expiration);
    }

    function permitAndBuyBundleWithErc20(
        address bidToken,
        uint256 bidAmount,
        TokenBundlePaymentObligation.ObligationData calldata askData,
        uint64 expiration,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        IERC20Permit bidTokenC = IERC20Permit(bidToken);
        try
            bidTokenC.permit(
                msg.sender,
                address(erc20Escrow),
                bidAmount,
                deadline,
                v,
                r,
                s
            )
        {} catch Error(string memory reason) {
            revert PermitFailed(bidToken, reason);
        } catch {
            revert PermitFailed(bidToken, "Unknown error");
        }

        return _buyBundleWithErc20(bidToken, bidAmount, askData, expiration);
    }

    function payErc20ForErc721(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid;
        try eas.getAttestation(buyAttestation) returns (
            Attestation memory _bid
        ) {
            bid = _bid;
        } catch {
            revert AttestationNotFound(buyAttestation);
        }

        ERC721EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC721EscrowObligation.ObligationData)
        );
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        return _payErc20ForErc721(buyAttestation, demand);
    }

    function payErc20ForErc1155(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid;
        try eas.getAttestation(buyAttestation) returns (
            Attestation memory _bid
        ) {
            bid = _bid;
        } catch {
            revert AttestationNotFound(buyAttestation);
        }

        ERC1155EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC1155EscrowObligation.ObligationData)
        );
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        return _payErc20ForErc1155(buyAttestation, demand);
    }

    function payErc20ForBundle(
        bytes32 buyAttestation
    ) external returns (bytes32) {
        Attestation memory bid;
        try eas.getAttestation(buyAttestation) returns (
            Attestation memory _bid
        ) {
            bid = _bid;
        } catch {
            revert AttestationNotFound(buyAttestation);
        }

        TokenBundleEscrowObligation.ObligationData memory escrowData = abi
            .decode(bid.data, (TokenBundleEscrowObligation.ObligationData));
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        return _payErc20ForBundle(buyAttestation, demand);
    }

    function permitAndPayErc20ForErc721(
        bytes32 buyAttestation,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        ERC721EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC721EscrowObligation.ObligationData)
        );
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        _permitPayment(demand, deadline, v, r, s);
        return _payErc20ForErc721(buyAttestation, demand);
    }

    function permitAndPayErc20ForErc1155(
        bytes32 buyAttestation,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        ERC1155EscrowObligation.ObligationData memory escrowData = abi.decode(
            bid.data,
            (ERC1155EscrowObligation.ObligationData)
        );
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        _permitPayment(demand, deadline, v, r, s);
        return _payErc20ForErc1155(buyAttestation, demand);
    }

    function permitAndPayErc20ForBundle(
        bytes32 buyAttestation,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (bytes32) {
        Attestation memory bid = eas.getAttestation(buyAttestation);
        TokenBundleEscrowObligation.ObligationData memory escrowData = abi
            .decode(bid.data, (TokenBundleEscrowObligation.ObligationData));
        ERC20PaymentObligation.ObligationData memory demand = abi.decode(
            escrowData.demand,
            (ERC20PaymentObligation.ObligationData)
        );

        _permitPayment(demand, deadline, v, r, s);
        return _payErc20ForBundle(buyAttestation, demand);
    }
}
