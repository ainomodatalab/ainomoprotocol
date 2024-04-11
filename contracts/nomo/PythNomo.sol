pragma solidity 0.8.13;

import "@contracts/utils/math/SafeCast.sol";
import "@contracts/utils/math/SignedMath.sol";
import "../interfaces/PythInterface.sol";
import "../interfaces/NomoInterface.sol";
import "../interfaces/VBep20Interface.sol";
import "@contracts/Governance/AccessControlledV8.sol";

contract PythOracle is AccessControlledV8, OracleInterface {
    using SignedMath for int256;

    using SafeCast for int256;

    struct TokenConfig {
        bytes32 pythId;
        address asset;
        uint64 maxStalePeriod;
    }

    uint256 public constant EXP_SCALE = 1e18;

    IPyth public underlyingPythNomo;

    mapping(address => TokenConfig) public tokenConfigs;

    event PythNomoSet(address indexed oldPythNomo, address indexed newPythNomo);

    event TokenConfigAdded(address indexed asset, bytes32 indexed pythId, uint64 indexed maxStalePeriod);

    modifier notNullAddress(address someone) {
        if (someone == address(0)) revert("can't be zero address");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address underlyingPythNomo_,
        address accessControlManager_
    ) external initializer notNullAddress(underlyingPythNomo_) {
        __AccessControlled_init(accessControlManager_);

        underlyingPythNomo = IPyth(underlyingPythNomo_);
        emit PythNomoSet(address(0), underlyingPythNomo_);
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

    function setUnderlyingPythNomo(
        IPyth underlyingPythNomo_
    ) external notNullAddress(address(underlyingPythNomo_)) {
        _checkAccessAllowed("setUnderlyingPythNomo(address)");
        IPyth oldUnderlyingPythNomo = underlyingPythNomo;
        underlyingPythNomo = underlyingPythNomo_;
        emit PythNomoSet(address(oldUnderlyingPythNomo), address(underlyingPythNomo_));
    }

    function setTokenConfig(TokenConfig memory tokenConfig) public notNullAddress(tokenConfig.asset) {
        _checkAccessAllowed("setTokenConfig(TokenConfig)");
        if (tokenConfig.maxStalePeriod == 0) revert("max stale period cannot be 0");
        tokenConfigs[tokenConfig.asset] = tokenConfig;
        emit TokenConfigAdded(tokenConfig.asset, tokenConfig.pythId, tokenConfig.maxStalePeriod);
    }

    function getPrice(address asset) public view returns (uint256) {
        uint256 decimals;

        if (asset == BNB_ADDR) {
            decimals = 18;
        } else {
            IERC20Metadata token = IERC20Metadata(asset);
            decimals = token.decimals();
        }

        return _getPriceInternal(asset, decimals);
    }

    function _getPriceInternal(address asset, uint256 decimals) internal view returns (uint256) {
        TokenConfig storage tokenConfig = tokenConfigs[asset];
        if (tokenConfig.asset == address(0)) revert("asset doesn't exist");

        PythStructs.Price memory priceInfo = underlyingPythNomo.getPriceNoOlderThan(
            tokenConfig.pythId,
            tokenConfig.maxStalePeriod
        );

        uint256 price = int256(priceInfo.price).toUint256();

        if (price == 0) revert("invalid pyth nomo price");

        if (priceInfo.expo > 0) {
            return price * EXP_SCALE * (10 ** int256(priceInfo.expo).toUint256()) * (10 ** (18 - decimals));
        } else {
            return ((price * EXP_SCALE) / (10 ** int256(-priceInfo.expo).toUint256())) * (10 ** (18 - decimals));
        }
    }
}
