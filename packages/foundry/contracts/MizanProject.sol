// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title MizanProject - Islamic Finance Rating Protocol
/// @author Mizan Project
/// @notice This contract manages Shariah compliance ratings for RWA protocols
/// @dev Implements role-based access control for rating submissions
contract MizanProject is AccessControl {
    /// @dev Role identifier for raters who can submit ratings
    bytes32 public constant RATER_ROLE = keccak256("RATER_ROLE");

    /// @notice Shariah compliance status of a protocol
    /// @dev Used to determine if protocol is compliant with Islamic finance principles
    enum ShariahStatus {
        NON_COMPLIANT,
        COMPLIANT,
        DOUBTFUL
    }

    /// @notice Asset types supported by the rating system
    enum AssetType {
        DEBT_BASED,
        EQUITY,
        COMMODITY,
        REAL_ESTATE,
        HYBRID
    }

    /// @dev Aggregated risk scores for a protocol
    /// @param transparency Transparency score (0-100)
    /// @param trackRecord Track record score (0-100)
    /// @param backing Asset backing score (0-100)
    /// @param smartContract Smart contract security score (0-100)
    /// @param liquidity Liquidity score (0-100)
    struct RiskScore {
        uint8 transparency;
        uint8 trackRecord;
        uint8 backing;
        uint8 smartContract;
        uint8 liquidity;
    }

    /// @notice Shariah compliance data for a protocol
    struct ShariahData {
        ShariahStatus status; /// Shariah compliance status
        AssetType assetType; /// Type of asset
        string fatwaIpfsCid; /// IPFS CID pointing to fatwa documentation
        bool hasPurificationMechanism; /// Whether protocol has purification mechanism for non-halal income
        string nonHalalSourceNotes; /// Notes on sources of non-halal income that need purification
    }

    /// @notice Complete protocol information and ratings
    /// @dev Stores all information needed to evaluate and display a protocol's rating
    struct ProtocolReport {
        string name; /// Protocol name (e.g., "Ondo US Dollar Yield")
        string symbol; /// Token symbol (e.g., "USDY")
        uint256 chainId; /// Blockchain network ID (e.g., 1 for Mainnet, 137 for Polygon)
        address tokenAddress; /// Token address on its native chain
        string website; /// Official protocol website URL
        RiskScore scores; /// Risk assessment scores
        ShariahData shariah; /// Shariah compliance information
        uint256 overallScore; /// Final weighted overall score (0-100)
        uint256 lastUpdate; /// Timestamp of last rating update
        address rater; /// Address of the rater who submitted this rating
        bool isListed; /// Whether this protocol is listed/active
    }

    /// @dev Mapping of protocol ID to its complete report data (using s_ prefix for storage)
    mapping(bytes32 => ProtocolReport) private s_protocols;

    /// @dev Array of all protocol IDs for enumeration and pagination (using s_ prefix for storage)
    bytes32[] private s_protocolIds;

    /// @notice Emitted when a protocol receives a new rating
    /// @param id Unique protocol identifier
    /// @param symbol Token symbol
    /// @param chainId Blockchain network ID
    /// @param score Overall rating score
    event ProtocolRated(bytes32 indexed id, string symbol, uint256 chainId, uint256 score);

    /// @notice Constructor - initializes the contract and grants roles
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RATER_ROLE, msg.sender);
    }

    // ============ PUBLIC FUNCTIONS ============

    /// @notice Generates a unique protocol ID from chain ID and token address
    /// @param _chainId The blockchain network ID
    /// @param _tokenAddress The token address on the native chain
    /// @return Unique bytes32 identifier for the protocol
    function getProtocolId(uint256 _chainId, address _tokenAddress) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_chainId, _tokenAddress));
    }

    /// @notice Submits or updates a protocol rating
    /// @dev Only callable by addresses with RATER_ROLE
    /// @param _name Protocol name
    /// @param _symbol Token symbol
    /// @param _chainId Blockchain network ID
    /// @param _tokenAddress Token address on native chain
    /// @param _website Official website URL
    /// @param _scores Risk assessment scores
    /// @param _shariah Shariah compliance information
    function submitRating(
        string memory _name,
        string memory _symbol,
        uint256 _chainId,
        address _tokenAddress,
        string memory _website,
        RiskScore calldata _scores,
        ShariahData calldata _shariah
    ) external onlyRole(RATER_ROLE) {
        bytes32 id = getProtocolId(_chainId, _tokenAddress);

        uint256 calculatedScore =
            ((_scores.transparency * 25)
                    + (_scores.trackRecord * 25)
                    + (_scores.backing * 20)
                    + (_scores.smartContract * 15)
                    + (_scores.liquidity * 15)) / 100;

        ProtocolReport storage report = s_protocols[id];

        if (!report.isListed) {
            s_protocolIds.push(id);
            report.isListed = true;
        }

        report.name = _name;
        report.symbol = _symbol;
        report.chainId = _chainId;
        report.tokenAddress = _tokenAddress;
        report.website = _website;

        report.scores = _scores;
        report.shariah = _shariah;
        report.overallScore = calculatedScore;
        report.lastUpdate = block.timestamp;
        report.rater = msg.sender;

        emit ProtocolRated(id, _symbol, _chainId, calculatedScore);
    }

    // ============ VIEW FUNCTIONS - GETTERS ============

    /// @notice Retrieves the complete protocol report by ID
    /// @param _id The unique protocol identifier
    /// @return The complete ProtocolReport struct
    function getProtocolById(bytes32 _id) external view returns (ProtocolReport memory) {
        return s_protocols[_id];
    }

    /// @notice Gets the total number of listed protocols
    /// @return The count of all protocols in the registry
    function getProtocolCount() external view returns (uint256) {
        return s_protocolIds.length;
    }

    /// @notice Retrieves a paginated slice of protocol IDs
    /// @dev Useful for frontend pagination without loading entire array into memory
    /// @param _offset Starting index in the protocol IDs array
    /// @param _limit Maximum number of IDs to return in this page
    /// @return Array of protocol IDs for the specified page
    function getProtocolIdsPaginated(uint256 _offset, uint256 _limit) external view returns (bytes32[] memory) {
        uint256 totalCount = s_protocolIds.length;

        // Handle edge cases
        if (_offset >= totalCount) {
            return new bytes32[](0);
        }

        // Calculate actual limit to avoid exceeding array bounds
        uint256 actualLimit = _limit;
        if (_offset + _limit > totalCount) {
            actualLimit = totalCount - _offset;
        }

        // Create result array and populate it
        bytes32[] memory result = new bytes32[](actualLimit);
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = s_protocolIds[_offset + i];
        }

        return result;
    }

    /// @notice Retrieves paginated protocol reports with their complete data
    /// @dev Combines pagination with data retrieval - useful for list views on frontend
    /// @param _offset Starting index
    /// @param _limit Maximum number of reports to return
    /// @return Array of ProtocolReport structs for the specified page
    function getProtocolsPaginated(uint256 _offset, uint256 _limit) external view returns (ProtocolReport[] memory) {
        bytes32[] memory ids = this.getProtocolIdsPaginated(_offset, _limit);
        ProtocolReport[] memory reports = new ProtocolReport[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            reports[i] = s_protocols[ids[i]];
        }

        return reports;
    }

    /// @notice Get all protocol data (WARNING: very gas intensive for large datasets - use pagination instead)
    /// @return Array of all ProtocolReport structs
    function getAllProtocols() external view returns (ProtocolReport[] memory) {
        ProtocolReport[] memory allProtocols = new ProtocolReport[](s_protocolIds.length);

        for (uint256 i = 0; i < s_protocolIds.length; i++) {
            allProtocols[i] = s_protocols[s_protocolIds[i]];
        }

        return allProtocols;
    }

    /// @notice Get all protocol IDs (WARNING: very gas intensive for large datasets - use pagination instead)
    /// @return Array of all protocol ID hashes stored in the contract
    function getAllProtocolIds() external view returns (bytes32[] memory) {
        return s_protocolIds;
    }
}
