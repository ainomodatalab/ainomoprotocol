pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./RouterHelper.sol";

contract SwapRouter is Ownable2Step, RouterHelper, ISwapRouter {
    using SafeERC20 for IERC20;

    address public immutable comptrollerAddress;

    uint256 private constant _NOT_ENTERED = 1;

    uint256 private constant _ENTERED = 2;

    address public BNBAddress;

    uint256 internal _status;

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) {
            revert SwapDeadlineExpire(deadline, block.timestamp);
        }
        _;
    }

    modifier ensurePath(address[] calldata path) {
        if (path.length < 2) {
            revert InvalidPath();
        }
        _;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) {
            revert ReentrantCheck();
        }
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    event SweepToken(address indexed token, address indexed to, uint256 sweepAmount);

    event BNBAddressUpdated(address indexed oldAddress, address indexed newAddress);

    constructor(
        address BNB_,
        address factory_,
        address _comptrollerAddress,
        address _BNBAddress
    ) RouterHelper(BNB_, factory_) {
        if (_comptrollerAddress == address(0) || _BNBAddress == address(0)) {
            revert ZeroAddress();
        }
        comptrollerAddress = _comptrollerAddress;
        _status = _NOT_ENTERED;
        BNBAddress = _BNBAddress;
    }

    receive() external payable {
        assert(msg.sender == WBNB); 
    }

    function setBNBAddress(address _BNBAddress) external onlyOwner {
        if (_BNBAddress == address(0)) {
            revert ZeroAddress();
        }

        _isTokenListed(_BNBAddress);

        address oldAddress = BNBAddress;
        BNBAddress = _BNBAddress;

        emit BNBAddressUpdated(oldAddress, BNBAddress);
    }

    function swapExactTokensForTokensAndSupply(
        address TokenAddress,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactTokensForTokensAndSupplyAtSupportingFee(
        address TokenAddress,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, address(this));
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactBNBForTokensAndSupply(
        address TokenAddress,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactBNBForTokens(amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactBNBForTokensAndSupplyAtSupportingFee(
        address TokenAddress,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactBNBForTokens(amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, address(this));
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapTokensForExactTokensAndSupply(
        address TokenAddress,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapTokensForExactTokens(amountOut, amountInMax, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapBNBForExactTokensAndSupply(
        address TokenAddress,
        uint256 amountOut,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapBNBForExactTokens(amountOut, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _supply(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactTokensForBNBAndSupply(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapExactTokensForBNB(amountIn, amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        _mintBNBandTransfer(swapAmount);
    }

    function swapExactTokensForBNBAndSupplyAtSupportingFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapExactTokensForBNB(amountIn, amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        if (swapAmount < amountOutMin) {
            revert SwapAmountLessThanAmountOutMin(swapAmount, amountOutMin);
        }
        _mintBNBandTransfer(swapAmount);
    }

    function swapTokensForExactBNBAndSupply(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapTokensForExactBNB(amountOut, amountInMax, path, address(this));
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        _mintBNBandTransfer(swapAmount);
    }

    function swapExactTokensForTokensAndRepay(
        address TokenAddress,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactTokensForTokensAndRepayAtSupportingFee(
        address TokenAddress,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, address(this));
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactBNBForTokensAndRepay(
        address TokenAddress,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactBNBForTokens(amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactBNBForTokensAndRepayAtSupportingFee(
        address TokenAddress,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapExactBNBForTokens(amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, address(this));
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapTokensForExactTokensAndRepay(
        address TokenAddress,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapTokensForExactTokens(amountOut, amountInMax, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapTokensForFullTokenDebtAndRepay(
        address TokenAddress,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        uint256 amountOut = IToken(TokenAddress).borrowBalanceCurrent(msg.sender);
        _swapTokensForExactTokens(amountOut, amountInMax, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapBNBForExactTokensAndRepay(
        address TokenAddress,
        uint256 amountOut,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        _swapBNBForExactTokens(amountOut, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapBNBForFullTokenDebtAndRepay(
        address TokenAddress,
        address[] calldata path,
        uint256 deadline
    ) external payable override nonReentrant ensure(deadline) ensurePath(path) {
        _ensureTokenChecks(TokenAddress, path[path.length - 1]);
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(address(this));
        uint256 amountOut = IToken(TokenAddress).borrowBalanceCurrent(msg.sender);
        _swapBNBForExactTokens(amountOut, path, address(this));
        uint256 swapAmount = _getSwapAmount(lastAsset, balanceBefore);
        _repay(lastAsset, TokenAddress, swapAmount);
    }

    function swapExactTokensForBNBAndRepay(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapExactTokensForBNB(amountIn, amountOutMin, path, address(this), TypesOfTokens.NON_SUPPORTING_FEE);
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        IBNB(BNBAddress).repayBorrowBehalf{ value: swapAmount }(msg.sender);
    }

    function swapExactTokensForBNBAndRepayAtSupportingFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapExactTokensForBNB(amountIn, amountOutMin, path, address(this), TypesOfTokens.SUPPORTING_FEE);
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        if (swapAmount < amountOutMin) {
            revert SwapAmountLessThanAmountOutMin(swapAmount, amountOutMin);
        }
        IBNB(BNBAddress).repayBorrowBehalf{ value: swapAmount }(msg.sender);
    }

    function swapTokensForExactBNBAndRepay(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        _swapTokensForExactBNB(amountOut, amountInMax, path, address(this));
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        IBNB(BNBAddress).repayBorrowBehalf{ value: swapAmount }(msg.sender);
    }

    function swapTokensForFullBNBDebtAndRepay(
        uint256 amountInMax,
        address[] calldata path,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) {
        uint256 balanceBefore = address(this).balance;
        uint256 amountOut = IToken(BNBAddress).borrowBalanceCurrent(msg.sender);
        _swapTokensForExactBNB(amountOut, amountInMax, path, address(this));
        uint256 balanceAfter = address(this).balance;
        uint256 swapAmount = balanceAfter - balanceBefore;
        IBNB(BNBAddress).repayBorrowBehalf{ value: swapAmount }(msg.sender);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override nonReentrant ensure(deadline) ensurePath(path) returns (uint256[] memory amounts) {
        amounts = _swapExactTokensForTokens(amountIn, amountOutMin, path, to, TypesOfTokens.NON_SUPPORTING_FEE);
    }

    function swapExactTokensForTokensAtSupportingFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override nonReentrant ensure(deadline) ensurePath(path) returns (uint256 swapAmount) {
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(to);
        _swapExactTokensForTokens(amountIn, amountOutMin, path, to, TypesOfTokens.SUPPORTING_FEE);
        swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, to);
    }

    function swapExactBNBForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        nonReentrant
        ensure(deadline)
        ensurePath(path)
        returns (uint256[] memory amounts)
    {
        amounts = _swapExactBNBForTokens(amountOutMin, path, to, TypesOfTokens.NON_SUPPORTING_FEE);
    }

    function swapExactBNBForTokensAtSupportingFee(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable virtual override nonReentrant ensure(deadline) ensurePath(path) returns (uint256 swapAmount) {
        address lastAsset = path[path.length - 1];
        uint256 balanceBefore = IERC20(lastAsset).balanceOf(to);
        _swapExactBNBForTokens(amountOutMin, path, to, TypesOfTokens.SUPPORTING_FEE);
        swapAmount = _checkForAmountOut(lastAsset, balanceBefore, amountOutMin, to);
    }

    function swapExactTokensForBNB(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) returns (uint256[] memory amounts) {
        amounts = _swapExactTokensForBNB(amountIn, amountOutMin, path, to, TypesOfTokens.NON_SUPPORTING_FEE);
    }

    function swapExactTokensForBNBAtSupportingFee(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override nonReentrant ensure(deadline) ensurePath(path) returns (uint256 swapAmount) {
        uint256 balanceBefore = to.balance;
        _swapExactTokensForBNB(amountIn, amountOutMin, path, to, TypesOfTokens.SUPPORTING_FEE);
        uint256 balanceAfter = to.balance;
        swapAmount = balanceAfter - balanceBefore;
        if (swapAmount < amountOutMin) {
            revert SwapAmountLessThanAmountOutMin(swapAmount, amountOutMin);
        }
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override nonReentrant ensure(deadline) ensurePath(path) returns (uint256[] memory amounts) {
        amounts = _swapTokensForExactTokens(amountOut, amountInMax, path, to);
    }

    function swapBNBForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        nonReentrant
        ensure(deadline)
        ensurePath(path)
        returns (uint256[] memory amounts)
    {
        amounts = _swapBNBForExactTokens(amountOut, path, to);
    }

    function swapTokensForExactBNB(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external virtual override nonReentrant ensure(deadline) ensurePath(path) returns (uint256[] memory amounts) {
        amounts = _swapTokensForExactBNB(amountOut, amountInMax, path, to);
    }

    function sweepToken(IERC20 token, address to, uint256 sweepAmount) external onlyOwner nonReentrant {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        uint256 balance = token.balanceOf(address(this));
        if (sweepAmount > balance) {
            revert InsufficientBalance(sweepAmount, balance);
        }
        token.safeTransfer(to, sweepAmount);

        emit SweepToken(address(token), to, sweepAmount);
    }

    function _supply(address path, address TokenAddress, uint256 swapAmount) internal {
        TransferHelper.safeApprove(path, TokenAddress, 0);
        TransferHelper.safeApprove(path, TokenAddress, swapAmount);
        uint256 response = IToken(TokenAddress).mintBehalf(msg.sender, swapAmount);
        if (response != 0) {
            revert SupplyError(msg.sender, TokenAddress, response);
        }
    }

    function _repay(address path, address TokenAddress, uint256 swapAmount) internal {
        TransferHelper.safeApprove(path, TokenAddress, 0);
        TransferHelper.safeApprove(path, TokenAddress, swapAmount);
        uint256 response = IToken(TokenAddress).repayBorrowBehalf(msg.sender, swapAmount);
        if (response != 0) {
            revert RepayError(msg.sender, TokenAddress, response);
        }
    }

    function _checkForAmountOut(
        address asset,
        uint256 balanceBefore,
        uint256 amountOutMin,
        address to
    ) internal view returns (uint256 swapAmount) {
        uint256 balanceAfter = IERC20(asset).balanceOf(to);
        swapAmount = balanceAfter - balanceBefore;
        if (swapAmount < amountOutMin) {
            revert SwapAmountLessThanAmountOutMin(swapAmount, amountOutMin);
        }
    }

    function _getSwapAmount(address asset, uint256 balanceBefore) internal view returns (uint256 swapAmount) {
        uint256 balanceAfter = IERC20(asset).balanceOf(address(this));
        swapAmount = balanceAfter - balanceBefore;
    }

    function _ensureTokenChecks(address TokenAddress, address underlying) internal {
        _isTokenListed(TokenAddress);
        if (IToken(TokenAddress).underlying() != underlying) {
            revert TokenUnderlyingInvalid(underlying);
        }
    }

    function _isTokenListed(address Token) internal view {
        bool isListed = InterfaceComptroller(comptrollerAddress).markets(Token);
        if (!isListed) {
            revert TokenNotListed(Token);
        }
    }

    function _mintBNBandTransfer(uint256 swapAmount) internal {
        uint256 BNBBalanceBefore = IBNB(BNBAddress).balanceOf(address(this));
        IBNB(BNBAddress).mint{ value: swapAmount }();
        uint256 BNBBalanceAfter = IBNB(BNBAddress).balanceOf(address(this));
        IERC20(BNBAddress).safeTransfer(msg.sender, (BNBBalanceAfter - BNBBalanceBefore));
    }
}
