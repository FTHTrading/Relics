// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title IIdentityRegistry
/// @notice Minimal ERC-3643-style KYC registry interface. The real UnyKorn ONCHAINID
///         IdentityRegistry (from PermissionedToken's 3-contract stack) implements this.
interface IIdentityRegistry {
    function isVerified(address account) external view returns (bool);
}

/// @title IComplianceModule
/// @notice Optional additional transfer-restriction hook (e.g. Reg D 506(c) accredited-only
///         gating, per-investor cap for Reg A+ Tier 2, jurisdiction blocklist). Pass the zero
///         address at deploy time to skip and rely on the identity registry alone.
interface IComplianceModule {
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);
}

/// @title ArtEditionSPV
/// @notice ERC-20 representing fractional membership interests in a single-purpose entity
///         that holds one physical art asset (or one named limited-edition series of a single
///         artist's work). Built for the OG4ever / Bottega Mortet catalog structuring exercise:
///         one deployment per SPV, gated by KYC through an IdentityRegistry, with a dust-free
///         pull-based proceeds distributor for eventual sale/royalty payouts to shareholders.
///
///         This is the security-token leg (Structuring Path A: Reg A+ Tier 2, or Path B:
///         Reg D 506(c)). Do NOT deploy for an asset a rights/licensing review has not cleared
///         -- see the "Structuring Tiers" sheet in the asset catalog for which pieces qualify.
///
/// @dev Toolchain: solc 0.8.24, optimizer 200 runs, evm_version paris, OpenZeppelin v5.0.2 --
///      matches the pinned smart-contract-builder / unykorn-studio compile pipeline.
contract ArtEditionSPV is ERC20, ERC20Permit, ERC20Pausable, AccessControl {
    bytes32 public constant COMPLIANCE_AGENT_ROLE = keccak256("COMPLIANCE_AGENT_ROLE");
    bytes32 public constant APPRAISER_ROLE = keccak256("APPRAISER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Immutable descriptive metadata for the underlying physical asset. Kept on-chain
    ///         so the token self-documents what it represents without relying solely on an
    ///         off-chain offering circular that could go stale or disappear.
    struct AssetInfo {
        string artist;          // e.g. "Dante Mortet"
        string title;           // e.g. "Golden Roots (Hugo Sanchez Feet Sculpture)"
        uint16 editionSize;     // total pieces in the edition; 1 for a unique work
        string spvEntityName;   // e.g. "OG4-BM-01 Golden Roots Series I LLC"
        string custodianName;   // insured custodian/vault holding the physical piece
        string metadataCID;     // IPFS CID of the ERC-721-style descriptive JSON (no ipfs:// prefix)
    }

    event AssetMetadataUpdated(string metadataCID);

    AssetInfo public assetInfo;
    IIdentityRegistry public identityRegistry;
    IComplianceModule public complianceModule; // address(0) == disabled

    /// @dev Accounts frozen under sanctions/AML review cannot send or receive, independent of
    ///      KYC-verified status (a verified account can still be frozen after onboarding).
    mapping(address => bool) public frozen;

    /// @dev Dust-free pull-based dividend accounting (magnified-per-share pattern) so proceeds
    ///      distribution never has to iterate over the holder set on-chain.
    uint256 private constant MAGNITUDE = 2 ** 128;
    uint256 private magnifiedDividendPerShare;
    mapping(address => int256) private magnifiedDividendCorrections;
    mapping(address => uint256) public withdrawnDividends;
    uint256 public totalDividendsDistributed;

    string public appraisalURI;
    uint256 public appraisalTimestamp;

    event AccountFrozen(address indexed account, bool frozen, string reason);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);
    event ProceedsDistributed(uint256 amount, uint256 newTotalDistributed);
    event DividendWithdrawn(address indexed to, uint256 amount);
    event AppraisalUpdated(string uri, uint256 timestamp);
    event ReceiptHash(bytes32 indexed receiptHash, string label);

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 totalShares_,
        AssetInfo memory assetInfo_,
        address identityRegistry_,
        address complianceModule_,
        address admin_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(identityRegistry_ != address(0), "SPV: identity registry required");
        require(admin_ != address(0), "SPV: admin required");
        assetInfo = assetInfo_;
        identityRegistry = IIdentityRegistry(identityRegistry_);
        complianceModule = IComplianceModule(complianceModule_);

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(COMPLIANCE_AGENT_ROLE, admin_);
        _grantRole(APPRAISER_ROLE, admin_);
        _grantRole(DISTRIBUTOR_ROLE, admin_);

        _mint(admin_, totalShares_);
    }

    // ---------------------------------------------------------------------
    // Compliance
    // ---------------------------------------------------------------------

    function setFrozen(address account, bool isFrozen, string calldata reason) external onlyRole(COMPLIANCE_AGENT_ROLE) {
        frozen[account] = isFrozen;
        emit AccountFrozen(account, isFrozen, reason);
    }

    /// @notice Regulator/court-ordered forced transfer (e.g. lost key recovery, fraud recovery,
    ///         estate settlement). Mirrors the forced-transfer pattern used across the
    ///         PermissionedToken / ERC-3643 stack.
    function forcedTransfer(address from, address to, uint256 amount, string calldata reason)
        external
        onlyRole(COMPLIANCE_AGENT_ROLE)
    {
        require(identityRegistry.isVerified(to), "SPV: recipient not KYC verified");
        _transfer(from, to, amount);
        emit ForcedTransfer(from, to, amount, reason);
    }

    function setComplianceModule(address complianceModule_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        complianceModule = IComplianceModule(complianceModule_);
    }

    // ---------------------------------------------------------------------
    // Appraisal / reporting (Reg A+ Tier 2 needs periodic audited valuation)
    // ---------------------------------------------------------------------

    function setAppraisal(string calldata uri) external onlyRole(APPRAISER_ROLE) {
        appraisalURI = uri;
        appraisalTimestamp = block.timestamp;
        emit AppraisalUpdated(uri, block.timestamp);
    }

    /// @notice Re-point the descriptive-metadata CID (image + attributes) produced by
    ///         build_ipfs_metadata.js. Distinct from setAppraisal -- this is what the piece
    ///         IS, appraisalURI is what it's currently WORTH.
    function setMetadataCID(string calldata metadataCID) external onlyRole(APPRAISER_ROLE) {
        assetInfo.metadataCID = metadataCID;
        emit AssetMetadataUpdated(metadataCID);
    }

    function metadataURI() external view returns (string memory) {
        return string.concat("ipfs://", assetInfo.metadataCID);
    }

    /// @notice Anchors an off-chain compliance/ops receipt hash on-chain, matching UnyKorn's
    ///         hash-chained ops.receipts pattern used elsewhere in the stack.
    function logReceipt(bytes32 receiptHash, string calldata label) external onlyRole(COMPLIANCE_AGENT_ROLE) {
        emit ReceiptHash(receiptHash, label);
    }

    // ---------------------------------------------------------------------
    // Proceeds distribution (dust-free magnified-per-share accumulator)
    // ---------------------------------------------------------------------

    /// @notice Called by DISTRIBUTOR_ROLE after off-chain sale/royalty proceeds land in the
    ///         SPV's bank/custody account and are wired to this contract as native value, or
    ///         tracked off-chain 1:1 -- adapt msg.value vs. an ERC-20 stablecoin pull as
    ///         needed for the actual settlement rail (USDF/USDC via MultiChainRegistry).
    function distributeProceeds() external payable onlyRole(DISTRIBUTOR_ROLE) {
        require(msg.value > 0, "SPV: no proceeds sent");
        require(totalSupply() > 0, "SPV: no shares outstanding");
        magnifiedDividendPerShare += (msg.value * MAGNITUDE) / totalSupply();
        totalDividendsDistributed += msg.value;
        emit ProceedsDistributed(msg.value, totalDividendsDistributed);
    }

    function withdrawableDividendOf(address account) public view returns (uint256) {
        return accumulativeDividendOf(account) - withdrawnDividends[account];
    }

    function accumulativeDividendOf(address account) public view returns (uint256) {
        int256 magnified = int256(magnifiedDividendPerShare * balanceOf(account))
            + magnifiedDividendCorrections[account];
        return uint256(magnified) / MAGNITUDE;
    }

    function withdrawDividend() external {
        uint256 amount = withdrawableDividendOf(msg.sender);
        require(amount > 0, "SPV: nothing to withdraw");
        withdrawnDividends[msg.sender] += amount;
        emit DividendWithdrawn(msg.sender, amount);
        (bool sent, ) = msg.sender.call{value: amount}("");
        require(sent, "SPV: withdrawal transfer failed");
    }

    // ---------------------------------------------------------------------
    // Pause
    // ---------------------------------------------------------------------

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Transfer gating + dividend-correction bookkeeping
    // ---------------------------------------------------------------------

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Pausable) {
        if (from != address(0)) {
            require(!frozen[from], "SPV: sender frozen");
            require(identityRegistry.isVerified(from), "SPV: sender not KYC verified");
        }
        if (to != address(0)) {
            require(!frozen[to], "SPV: recipient frozen");
            require(identityRegistry.isVerified(to), "SPV: recipient not KYC verified");
        }
        if (from != address(0) && to != address(0) && address(complianceModule) != address(0)) {
            require(complianceModule.canTransfer(from, to, value), "SPV: compliance module rejected transfer");
        }

        super._update(from, to, value);

        int256 magCorrection = int256(magnifiedDividendPerShare * value);
        if (from != address(0)) {
            magnifiedDividendCorrections[from] += magCorrection;
        }
        if (to != address(0)) {
            magnifiedDividendCorrections[to] -= magCorrection;
        }
    }
}
