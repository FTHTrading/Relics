// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

interface IIdentityRegistryLite {
    function isVerified(address account) external view returns (bool);
}

/// @title ArtCustodyReceipt
/// @notice ERC-721 whole-object custody receipt: 1 token = 100% title to one specific physical
///         item (a trading card, a single sculpture, a single memorabilia piece) held in
///         insured third-party custody. No pooling, no managerial profit expectation baked
///         into the token itself -- this is the non-security leg (Structuring Path C) for the
///         OG4ever catalog items where fractional investment framing isn't the goal, notably
///         Murray Henderson's "Beautiful Dozen" trading card set.
///
///         Distinct from ArtEditionSPV: that contract sells fractional shares of a pooled
///         asset for investment. This contract sells/transfers outright title to one physical
///         object with a redemption path back to the physical world. Keeping them separate
///         contracts, not a mode flag on one contract, is deliberate -- it keeps the Howey
///         analysis clean for whichever one a given asset uses.
///
/// @dev Toolchain: solc 0.8.24, optimizer 200 runs, evm_version paris, OpenZeppelin v5.0.2.
contract ArtCustodyReceipt is ERC721, AccessControl, EIP712 {
    using ECDSA for bytes32;

    bytes32 public constant CUSTODIAN_ROLE = keccak256("CUSTODIAN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    bytes32 private constant ATTESTATION_TYPEHASH =
        keccak256("CustodyAttestation(uint256 tokenId,bytes32 conditionHash,uint256 attestedAt)");

    struct ItemInfo {
        string artist;
        string title;
        string physicalDescription; // condition, dimensions, medium
        string custodianName;
        bool requireVerification;   // gate transfers behind identityRegistry.isVerified
        bool redemptionRequested;
        bool redeemed;
        string metadataCID;         // IPFS CID of the ERC-721 metadata JSON (no ipfs:// prefix)
    }

    mapping(uint256 => ItemInfo) public items;
    mapping(uint256 => bytes32) public latestAttestationHash;
    mapping(uint256 => uint256) public latestAttestationAt;

    IIdentityRegistryLite public identityRegistry; // may be address(0) if never gating transfers
    uint256 private _nextTokenId = 1;

    event ItemMinted(uint256 indexed tokenId, string artist, string title, string custodianName);
    event RedemptionRequested(uint256 indexed tokenId, address indexed holder);
    event Redeemed(uint256 indexed tokenId, address indexed holder, string shippingReceiptHash);
    event CustodyAttested(uint256 indexed tokenId, bytes32 conditionHash, uint256 attestedAt, address signer);
    event MetadataUpdated(uint256 indexed tokenId, string metadataCID);

    constructor(string memory name_, string memory symbol_, address identityRegistry_, address admin_)
        ERC721(name_, symbol_)
        EIP712(name_, "1")
    {
        require(admin_ != address(0), "Custody: admin required");
        identityRegistry = IIdentityRegistryLite(identityRegistry_); // zero address allowed = ungated
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(CUSTODIAN_ROLE, admin_);
        _grantRole(MINTER_ROLE, admin_);
    }

    function mint(address to, ItemInfo calldata info) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        items[tokenId] = info;
        items[tokenId].redemptionRequested = false;
        items[tokenId].redeemed = false;
        _safeMint(to, tokenId);
        emit ItemMinted(tokenId, info.artist, info.title, info.custodianName);
    }

    /// @notice Holder-initiated request to redeem the token for the physical object. The
    ///         custodian executes shipment/handoff off-chain, then calls completeRedemption.
    function requestRedemption(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Custody: not token owner");
        require(!items[tokenId].redeemed, "Custody: already redeemed");
        items[tokenId].redemptionRequested = true;
        emit RedemptionRequested(tokenId, msg.sender);
    }

    function completeRedemption(uint256 tokenId, string calldata shippingReceiptHash)
        external
        onlyRole(CUSTODIAN_ROLE)
    {
        require(items[tokenId].redemptionRequested, "Custody: no redemption request on file");
        require(!items[tokenId].redeemed, "Custody: already redeemed");
        address holder = ownerOf(tokenId);
        items[tokenId].redeemed = true;
        _burn(tokenId);
        emit Redeemed(tokenId, holder, shippingReceiptHash);
    }

    /// @notice Custodian signs an EIP-712 attestation that the item is verified present and in
    ///         the described condition as of attestedAt -- a proof-of-custody heartbeat, same
    ///         pattern as the RWAOracle / ProofOfReserveConsumer attestation flow elsewhere in
    ///         the library. conditionHash should be keccak256 of an off-chain condition report
    ///         (photos, weight, appraisal note).
    function attestCustody(
        uint256 tokenId,
        bytes32 conditionHash,
        uint256 attestedAt,
        bytes calldata signature
    ) external {
        bytes32 structHash = keccak256(abi.encode(ATTESTATION_TYPEHASH, tokenId, conditionHash, attestedAt));
        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);
        require(hasRole(CUSTODIAN_ROLE, signer), "Custody: signer not an authorized custodian");
        require(attestedAt <= block.timestamp, "Custody: attestation timestamped in the future");
        latestAttestationHash[tokenId] = conditionHash;
        latestAttestationAt[tokenId] = attestedAt;
        emit CustodyAttested(tokenId, conditionHash, attestedAt, signer);
    }

    function setIdentityRegistry(address identityRegistry_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        identityRegistry = IIdentityRegistryLite(identityRegistry_);
    }

    /// @notice Standard ERC-721 metadata pointer -- resolves to the offline-hashed,
    ///         IPFS-pinned JSON produced by build_ipfs_metadata.js / pin_to_ipfs.js.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        return string.concat("ipfs://", items[tokenId].metadataCID);
    }

    /// @notice Re-point a token's metadata CID (e.g. after a corrected appraisal or
    ///         condition report is re-pinned). Emits an event so the change is auditable --
    ///         the OLD CID is still retrievable from IPFS/event logs, nothing is erased.
    function setMetadataCID(uint256 tokenId, string calldata metadataCID) external onlyRole(CUSTODIAN_ROLE) {
        items[tokenId].metadataCID = metadataCID;
        emit MetadataUpdated(tokenId, metadataCID);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0) && address(identityRegistry) != address(0)) {
            if (items[tokenId].requireVerification) {
                require(identityRegistry.isVerified(to), "Custody: recipient not KYC verified");
            }
        }
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
