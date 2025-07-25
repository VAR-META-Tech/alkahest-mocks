// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {ERC20EscrowObligation} from "@src/obligations/ERC20EscrowObligation.sol";
import {ERC20PaymentObligation} from "@src/obligations/ERC20PaymentObligation.sol";
import {ERC20BarterUtils} from "@src/utils/ERC20BarterUtils.sol";
import {IEAS} from "@eas/IEAS.sol";
import {ISchemaRegistry} from "@eas/ISchemaRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {EASDeployer} from "@test/utils/EASDeployer.sol";

contract MockERC20Permit is ERC20Permit {
    constructor(
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) ERC20Permit(name) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }
}

contract ERC20BarterUtilsUnitTest is Test {
    ERC20EscrowObligation public escrowObligation;
    ERC20PaymentObligation public paymentObligation;
    ERC20BarterUtils public barterUtils;
    MockERC20Permit public erc20TokenA;
    MockERC20Permit public erc20TokenB;
    IEAS public eas;
    ISchemaRegistry public schemaRegistry;

    uint256 internal constant ALICE_PRIVATE_KEY = 0xa11ce;
    uint256 internal constant BOB_PRIVATE_KEY = 0xb0b;

    address public alice;
    address public bob;

    function setUp() public {
        EASDeployer easDeployer = new EASDeployer();
        (eas, schemaRegistry) = easDeployer.deployEAS();

        alice = vm.addr(ALICE_PRIVATE_KEY);
        bob = vm.addr(BOB_PRIVATE_KEY);

        erc20TokenA = new MockERC20Permit("Token A", "TKA");
        erc20TokenB = new MockERC20Permit("Token B", "TKB");

        escrowObligation = new ERC20EscrowObligation(eas, schemaRegistry);
        paymentObligation = new ERC20PaymentObligation(eas, schemaRegistry);
        barterUtils = new ERC20BarterUtils(
            eas,
            escrowObligation,
            paymentObligation
        );

        erc20TokenA.transfer(alice, 1000 * 10 ** 18);
        erc20TokenB.transfer(bob, 1000 * 10 ** 18);
    }

    function testBuyErc20ForErc20() public {
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 200 * 10 ** 18;
        uint64 expiration = uint64(block.timestamp + 1 days);

        vm.startPrank(alice);
        erc20TokenA.approve(address(escrowObligation), bidAmount);
        bytes32 buyAttestation = barterUtils.buyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration
        );
        vm.stopPrank();

        assertNotEq(
            buyAttestation,
            bytes32(0),
            "Buy attestation should be created"
        );
    }

    function testPermitAndBuyErc20ForErc20() public {
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 200 * 10 ** 18;
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenA,
            ALICE_PRIVATE_KEY,
            address(escrowObligation),
            bidAmount,
            deadline
        );

        vm.prank(alice);
        bytes32 buyAttestation = barterUtils.permitAndBuyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration,
            deadline,
            v,
            r,
            s
        );

        assertNotEq(
            buyAttestation,
            bytes32(0),
            "Buy attestation should be created"
        );
    }

    function testPermitSignatureValidation() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenA,
            ALICE_PRIVATE_KEY,
            address(escrowObligation),
            amount,
            deadline
        );

        erc20TokenA.permit(
            alice,
            address(escrowObligation),
            amount,
            deadline,
            v,
            r,
            s
        );

        assertEq(
            erc20TokenA.allowance(alice, address(escrowObligation)),
            amount,
            "Permit should have set allowance"
        );
    }

    function test_RevertWhen_PermitExpired() public {
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 200 * 10 ** 18;
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenA,
            ALICE_PRIVATE_KEY,
            address(escrowObligation),
            bidAmount,
            deadline
        );

        vm.warp(block.timestamp + 2);

        vm.prank(alice);
        vm.expectRevert();
        barterUtils.permitAndBuyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration,
            deadline,
            v,
            r,
            s
        );
    }

    function testPermitAndBuyWithErc20() public {
        uint256 amount = 100 * 10 ** 18;
        address arbiter = address(this);
        bytes memory demand = abi.encode("test demand");
        uint64 expiration = uint64(block.timestamp + 1 days);
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenA,
            ALICE_PRIVATE_KEY,
            address(escrowObligation),
            amount,
            deadline
        );

        vm.prank(alice);
        bytes32 escrowId = barterUtils.permitAndBuyWithErc20(
            address(erc20TokenA),
            amount,
            arbiter,
            demand,
            expiration,
            deadline,
            v,
            r,
            s
        );

        assertNotEq(
            escrowId,
            bytes32(0),
            "Escrow attestation should be created"
        );
    }

    function testPermitAndPayWithErc20() public {
        uint256 amount = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenA,
            ALICE_PRIVATE_KEY,
            address(paymentObligation),
            amount,
            deadline
        );

        vm.prank(alice);
        bytes32 paymentId = barterUtils.permitAndPayWithErc20(
            address(erc20TokenA),
            amount,
            bob,
            deadline,
            v,
            r,
            s
        );

        assertNotEq(
            paymentId,
            bytes32(0),
            "Payment attestation should be created"
        );
    }

    function testPayErc20ForErc20() public {
        // First create a buy attestation
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 200 * 10 ** 18;
        uint64 expiration = uint64(block.timestamp + 1 days);

        vm.startPrank(alice);
        erc20TokenA.approve(address(escrowObligation), bidAmount);
        bytes32 buyAttestation = barterUtils.buyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration
        );
        vm.stopPrank();

        // Now pay for it
        vm.startPrank(bob);
        erc20TokenB.approve(address(paymentObligation), askAmount);
        bytes32 sellAttestation = barterUtils.payErc20ForErc20(buyAttestation);
        vm.stopPrank();

        assertNotEq(
            sellAttestation,
            bytes32(0),
            "Sell attestation should be created"
        );

        // Verify the payment went through
        assertEq(
            erc20TokenA.balanceOf(bob),
            bidAmount,
            "Bob should have received Token A"
        );
        assertEq(
            erc20TokenB.balanceOf(alice),
            askAmount,
            "Alice should have received Token B"
        );
    }

    function testPermitAndPayErc20ForErc20() public {
        // First create a buy attestation
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 200 * 10 ** 18;
        uint64 expiration = uint64(block.timestamp + 1 days);

        vm.startPrank(alice);
        erc20TokenA.approve(address(escrowObligation), bidAmount);
        bytes32 buyAttestation = barterUtils.buyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration
        );
        vm.stopPrank();

        // Now pay for it using permit
        uint256 deadline = block.timestamp + 1;

        (uint8 v, bytes32 r, bytes32 s) = _getPermitSignature(
            erc20TokenB,
            BOB_PRIVATE_KEY,
            address(paymentObligation),
            askAmount,
            deadline
        );

        vm.prank(bob);
        bytes32 sellAttestation = barterUtils.permitAndPayErc20ForErc20(
            buyAttestation,
            deadline,
            v,
            r,
            s
        );

        assertNotEq(
            sellAttestation,
            bytes32(0),
            "Sell attestation should be created"
        );

        // Verify the payment went through
        assertEq(
            erc20TokenA.balanceOf(bob),
            bidAmount,
            "Bob should have received Token A"
        );
        assertEq(
            erc20TokenB.balanceOf(alice),
            askAmount,
            "Alice should have received Token B"
        );
    }

    function test_RevertWhen_PaymentCollectionFails() public {
        // First create a buy attestation with a large amount
        uint256 bidAmount = 100 * 10 ** 18;
        uint256 askAmount = 2000 * 10 ** 18; // More than Bob has
        uint64 expiration = uint64(block.timestamp + 1 days);

        vm.startPrank(alice);
        erc20TokenA.approve(address(escrowObligation), bidAmount);
        bytes32 buyAttestation = barterUtils.buyErc20ForErc20(
            address(erc20TokenA),
            bidAmount,
            address(erc20TokenB),
            askAmount,
            expiration
        );
        vm.stopPrank();

        // Now try to pay for it, but Bob doesn't have enough tokens
        vm.startPrank(bob);
        erc20TokenB.approve(address(paymentObligation), askAmount);
        vm.expectRevert(); // Should revert as the payment collection will fail
        barterUtils.payErc20ForErc20(buyAttestation);
        vm.stopPrank();
    }

    function _getPermitSignature(
        MockERC20Permit token,
        uint256 ownerPrivateKey,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 permitTypehash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        address owner = vm.addr(ownerPrivateKey);
        bytes32 structHash = keccak256(
            abi.encode(
                permitTypehash,
                owner,
                spender,
                value,
                token.nonces(owner),
                deadline
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        (v, r, s) = vm.sign(ownerPrivateKey, digest);
    }
}
