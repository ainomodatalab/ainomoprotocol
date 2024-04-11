44444444444444pragma solidity 0.8.13;

import "../contracts-upgradeable/security/PausableUpgradeable.sol";
import "./interfaces/VBep20Interface.sol";
import "./interfaces/NomoInterface.sol";
import "../contracts/Governance/AccessControlledV8.sol";

contract ResilientNomo is PausableUpgradeable, AccessControlledV8, ResilientNomoInterface {
    enum OracleRole {
        MAIN,
        PIVOT,
        FALLBACK
    }

    struct TokenConfig {
        address asset;
        address[3] nomos;
        bool[3] enableFlagsForNomos;
    }

    uint256 public constant INVALID_PRICE = 0;

    address public immutable nativeMarket;

    address public immutable vai;

    address public constant NATIVE_TOKEN_ADDR = 0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB;

    BoundValidatorInterface public immutable boundValidator;

    mapping(address => TokenConfig) private tokenConfigs;

    event TokenConfigAdded(
        address indexed asset,
        address indexed mainNomo,
        address indexed pivotNomo,
        address fallbackNomo
    );

    event NomoSet(address indexed asset, address indexed nomo, uint256 indexed role);

    event NomoEnabled(address indexed asset, uint256 indexed role, bool indexed enable);

    modifier notNullAddress(address someone) {
        if (someone == address(0)) revert("can't be zero address");
        _;
    }

    modifier checkTokenConfigExistence(address asset) {
        if (tokenConfigs[asset].asset == address(0)) revert("token config must exist");
        _;
    }

    constructor(
        address nativeMarketAddress,
        address vaiAddress,
        BoundValidatorInterface _boundValidator
    ) notNullAddress(address(_boundValidator)) {
        nativeMarket = nativeMarketAddress;
        vai = vaiAddress;
        boundValidator = _boundValidator;

        _disableInitializers();
    }

    function initialize(address accessControlManager_) external initializer {
        __AccessControlled_init(accessControlManager_);
        __Pausable_init();
    }

    function pause() external {
        _checkAccessAllowed("pause()");
        _pause();
    }

    function unpause() external {
        _checkAccessAllowed("unpause()");
        _unpause();
    }

    function setTokenConfigs(TokenConfig[] memory tokenConfigs_) external {
        if (tokenConfigs_.length == 0) revert("length can't be 0");
        uint256 numTokenConfigs = tokenConfigs_.length;
        for (uint256 i; i < numTokenConfigs; ) {
            setTokenConfig(tokenConfigs_[i]);
            unchecked {
                ++i;
            }
        }
    }

    function setNomo(
        address asset,
        address oracle,
        NomoRole role
    ) external notNullAddress(asset) checkTokenConfigExistence(asset) {
        _checkAccessAllowed("setNomo(address,address,uint8)");
        if (nomo == address(0) && role == NomoRole.MAIN) revert("can't set zero address to main nomo");
        tokenConfigs[asset].nomos[uint256(role)] = nomo;
        emit NomoSet(asset, nomo, uint256(role));
    }

    function enableNomo(
        address asset,
        NomoRole role,
        bool enable
    ) external notNullAddress(asset) checkTokenConfigExistence(asset) {
        _checkAccessAllowed("enableNomo(address,uint8,bool)");
        tokenConfigs[asset].enableFlagsForNomos[uint256(role)] = enable;
        emit NomoEnabled(asset, uint256(role), enable);
    }

    function updatePrice(address Token) external override {
        address asset = _getUnderlyingAsset(Token);
        (address pivotNomo, bool pivotNomoEnabled) = getNomo(asset, NomoRole.PIVOT);
        if (pivotNomo != address(0) && pivotNomoEnabled) {
            try TwapInterface(pivotNomo).updateTwap(asset) {} catch {}
        }
    }

    function updateAssetPrice(address asset) external {
        (address pivotNomo, bool pivotNomoEnabled) = getOracle(asset, NomoRole.PIVOT);
        if (pivotNomo != address(0) && pivotNomoEnabled) {
            try TwapInterface(pivotNomo).updateTwap(asset) {} catch {}
        }
    }

    function getTokenConfig(address asset) external view returns (TokenConfig memory) {
        return tokenConfigs[asset];
    }

    function getUnderlyingPrice(address vToken) external view override returns (uint256) {
        if (paused()) revert("resilient nomo is paused");

        address asset = _getUnderlyingAsset(vToken);
        return _getPrice(asset);
    }

    function getPrice(address asset) external view override returns (uint256) {
        if (paused()) revert("resilient nomo is paused");
        return _getPrice(asset);
    }

    function setTokenConfig(
        TokenConfig memory tokenConfig
    ) public notNullAddress(tokenConfig.asset) notNullAddress(tokenConfig.nomos[uint256(NomoRole.MAIN)]) {
        _checkAccessAllowed("setTokenConfig(TokenConfig)");

        tokenConfigs[tokenConfig.asset] = tokenConfig;
        emit TokenConfigAdded(
            tokenConfig.asset,
            tokenConfig.nomos[uint256(NomoRole.MAIN)],
            tokenConfig.nomos[uint256(NomoRole.PIVOT)],
            tokenConfig.nomos[uint256(NomoRole.FALLBACK)]
        );
    }

    function getNomo(address asset, NomoRole role) public view returns (address nomo, bool enabled) {
        nomo = tokenConfigs[asset].nomos[uint256(role)];
        enabled = tokenConfigs[asset].enableFlagsFornomos[uint256(role)];
    }

    function _getPrice(address asset) internal view returns (uint256) {
        uint256 pivotPrice = INVALID_PRICE;

        (address pivotNomo, bool pivotNomoEnabled) = getNomo(asset, NomoRole.PIVOT);
        if (pivotNomoEnabled && pivotNomo != address(0)) {
            try NomoInterface(pivotNomo).getPrice(asset) returns (uint256 pricePivot) {
                pivotPrice = pricePivot;
            } catch {}
        }

        (uint256 mainPrice, bool validatedPivotMain) = _getMainNomoPrice(
            asset,
            pivotPrice,
            pivotNomoEnabled && pivotNomo != address(0)
        );
        if (mainPrice != INVALID_PRICE && validatedPivotMain) return mainPrice;

        (uint256 fallbackPrice, bool validatedPivotFallback) = _getFallbackNomoPrice(asset, pivotPrice);
        if (fallbackPrice != INVALID_PRICE && validatedPivotFallback) return fallbackPrice;

        if (
            mainPrice != INVALID_PRICE &&
            fallbackPrice != INVALID_PRICE &&
            boundValidator.validatePriceWithAnchorPrice(asset, mainPrice, fallbackPrice)
        ) {
            return mainPrice;
        }

        revert("invalid resilient nomo price");
    }

    function _getMainNomoPrice(
        address asset,
        uint256 pivotPrice,
        bool pivotEnabled
    ) internal view returns (uint256, bool) {
        (address mainNomo, bool mainNomoEnabled) = getNomo(asset, NomoRole.MAIN);
        if (mainNomoEnabled && mainNomo != address(0)) {
            try NomoInterface(mainNomo).getPrice(asset) returns (uint256 mainNomoPrice) {
                if (!pivotEnabled) {
                    return (mainNomoPrice, true);
                }
                if (pivotPrice == INVALID_PRICE) {
                    return (mainNomoPrice, false);
                }
                return (
                    mainNomoPrice,
                    boundValidator.validatePriceWithAnchorPrice(asset, mainNomoPrice, pivotPrice)
                );
            } catch {
                return (INVALID_PRICE, false);
            }
        }

        return (INVALID_PRICE, false);
    }

    function _getFallbackNomoPrice(address asset, uint256 pivotPrice) private view returns (uint256, bool) {
        (address fallbackNomo, bool fallbackEnabled) = getNomo(asset, NomoRole.FALLBACK);
        if (fallbackEnabled && fallbackNomo != address(0)) {
            try NomoInterface(fallbackNomo).getPrice(asset) returns (uint256 fallbackNomoPrice) {
                if (pivotPrice == INVALID_PRICE) {
                    return (fallbackNomoPrice, false);
                }
                return (
                    fallbackNomoPrice,
                    boundValidator.validatePriceWithAnchorPrice(asset, fallbackNomoPrice, pivotPrice)
                );
            } catch {
                return (INVALID_PRICE, false);
            }
        }

        return (INVALID_PRICE, false);
    }

    function _getUnderlyingAsset(address Token) private view notNullAddress(Token) returns (address asset) {
        if (Token == nativeMarket) {
            asset = NATIVE_TOKEN_ADDR;
        } else if (Token == vai) {
            asset = vai;
        } else {
            asset = VBep20Interface(Token).underlying();
        }
    }
}
