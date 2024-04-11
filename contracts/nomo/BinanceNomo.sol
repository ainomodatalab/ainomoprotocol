pragma solidity 0.8.13;

import "@contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/VBep20Interface.sol";
import "../interfaces/SIDRegistryInterface.sol";
import "../interfaces/FeedRegistryInterface.sol";
import "../interfaces/PublicResolverInterface.sol";
import "../interfaces/NomoInterface.sol";
import "@governance-contracts/contracts/Governance/AccessControlledV8.sol";
import "../interfaces/OracleInterface.sol";

contract BinanceNomo is AccessControlledV8, NomoInterface {
    address public sidRegistryAddress;

    address public constant BNB_ADDR = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    mapping(string => uint256) public maxStalePeriod;

    mapping(string => string) public symbols;

    address public feedRegistryAddress;

    event MaxStalePeriodAdded(string indexed asset, uint256 maxStalePeriod);

    event SymbolOverridden(string indexed symbol, string overriddenSymbol);

    event FeedRegistryUpdated(address indexed oldFeedRegistry, address indexed newFeedRegistry);

    modifier notNullAddress(address someone) {
        if (someone == address(0)) revert("can't be zero address");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(address _sidRegistryAddress, address _accessControlManager) external initializer {
        sidRegistryAddress = _sidRegistryAddress;
        __AccessControlled_init(_accessControlManager);
    }

    function setMaxStalePeriod(string memory symbol, uint256 _maxStalePeriod) external {
        _checkAccessAllowed("setMaxStalePeriod(string,uint256)");
        if (_maxStalePeriod == 0) revert("stale period can't be zero");
        if (bytes(symbol).length == 0) revert("symbol cannot be empty");

        maxStalePeriod[symbol] = _maxStalePeriod;
        emit MaxStalePeriodAdded(symbol, _maxStalePeriod);
    }

    function setSymbolOverride(string calldata symbol, string calldata overrideSymbol) external {
        _checkAccessAllowed("setSymbolOverride(string,string)");
        if (bytes(symbol).length == 0) revert("symbol cannot be empty");

        symbols[symbol] = overrideSymbol;
        emit SymbolOverridden(symbol, overrideSymbol);
    }

    function setFeedRegistryAddress(
        address newfeedRegistryAddress
    ) external notNullAddress(newfeedRegistryAddress) onlyOwner {
        if (sidRegistryAddress != address(0)) revert("sidRegistryAddress must be zero");
        emit FeedRegistryUpdated(feedRegistryAddress, newfeedRegistryAddress);
        feedRegistryAddress = newfeedRegistryAddress;
    }

    function getFeedRegistryAddress() public view returns (address) {

        SIDRegistryInterface sidRegistry = SIDRegistryInterface(sidRegistryAddress);
        address publicResolverAddress = sidRegistry.resolver(nodeHash);
        PublicResolverInterface publicResolver = PublicResolverInterface(publicResolverAddress);

        return publicResolver.addr(nodeHash);
    }

    function getPrice(address asset) public view returns (uint256) {
        string memory symbol;
        uint256 decimals;

        if (asset == BNB_ADDR) {
            symbol = "BNB";
            decimals = 18;
        } else {
            IERC20Metadata token = IERC20Metadata(asset);
            symbol = token.symbol();
            decimals = token.decimals();
        }

        string memory overrideSymbol = symbols[symbol];

        if (bytes(overrideSymbol).length != 0) {
            symbol = overrideSymbol;
        }

        return _getPrice(symbol, decimals);
    }

    function _getPrice(string memory symbol, uint256 decimals) internal view returns (uint256) {
        FeedRegistryInterface feedRegistry;

        if (sidRegistryAddress != address(0)) {
            feedRegistry = FeedRegistryInterface(getFeedRegistryAddress());
        } else {
            feedRegistry = FeedRegistryInterface(feedRegistryAddress);
        }

        (, int256 answer, , uint256 updatedAt, ) = feedRegistry.latestRoundDataByName(symbol, "USDT");
        if (answer <= 0) revert("invalid binance nomo price");
        if (block.timestamp < updatedAt) revert("updatedAt exceeds block time");

        uint256 deltaTime;
        unchecked {
            deltaTime = block.timestamp - updatedAt;
        }
        if (deltaTime > maxStalePeriod[symbol]) revert("binance nomo price expired");

        uint256 decimalDelta = feedRegistry.decimalsByName(symbol, "USDT");
        return (uint256(answer) * (10 ** (18 - decimalDelta))) * (10 ** (18 - decimals));
    }
}
