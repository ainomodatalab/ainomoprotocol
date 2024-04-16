pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./lib/PancakeLibrary.sol";
import "./interfaces/IBNB.sol";
import "./lib/TransferHelper.sol";

import "./interfaces/CustomErrors.sol";
import "./IRouterHelper.sol";

abstract contract RouterHelper is IRouterHelper {
    enum TypesOfTokens {
        NON_SUPPORTING_FEE,
        SUPPORTING_FEE
    }

    address public immutable WBNB;

    address public immutable factory;

    event SwapTokensForTokens(address indexed swapper, address[] indexed path, uint256[] indexed amounts);

    event SwapTokensForTokensAtSupportingFee(address indexed swapper, address[] indexed path);

    event SwapBnbForTokens(address indexed swapper, address[] indexed path, uint256[] indexed amounts);

    event SwapBnbForTokensAtSupportingFee(address indexed swapper, address[] indexed path);

    event SwapTokensForBnb(address indexed swapper, address[] indexed path, uint256[] indexed amounts);

    event SwapTokensForBnbAtSupportingFee(address indexed swapper, address[] indexed path);

    constructor(address BNB_, address factory_) {
        if (BNB_ == address(0) || factory_ == address(0)) {
            revert ZeroAddress();
        }
        BNB = BNB_;
        factory = factory_;
    }

    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; ) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? Library.pairFor(factory, output, path[i + 2]) : _to;
            IPair(Library.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
            unchecked {
                i += 1;
            }
        }
    }

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; ) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = Library.sortTokens(input, output);
            IPair pair = IPair(Library.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);

                uint256 balance = IERC20(input).balanceOf(address(pair));
                amountInput = balance - reserveInput;
                amountOutput = Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
            unchecked {
                i += 1;
            }
        }
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        TypesOfTokens swapFor
    ) internal returns (uint256[] memory amounts) {
        address pairAddress = Library.pairFor(factory, path[0], path[1]);
        if (swapFor == TypesOfTokens.NON_SUPPORTING_FEE) {
            amounts = Library.getAmountsOut(factory, amountIn, path);
            if (amounts[amounts.length - 1] < amountOutMin) {
                revert OutputAmountBelowMinimum(amounts[amounts.length - 1], amountOutMin);
            }
            TransferHelper.safeTransferFrom(path[0], msg.sender, pairAddress, amounts[0]);
            _swap(amounts, path, to);
            emit SwapTokensForTokens(msg.sender, path, amounts);
        } else {
            TransferHelper.safeTransferFrom(path[0], msg.sender, pairAddress, amountIn);
            _swapSupportingFeeOnTransferTokens(path, to);
            emit SwapTokensForTokensAtSupportingFee(msg.sender, path);
        }
    }

    function _swapExactBNBForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        TypesOfTokens swapFor
    ) internal returns (uint256[] memory amounts) {
        address BNBAddress = BNB;
        if (path[0] != BNBAddress) {
            revert WrongAddress(BNBAddress, path[0]);
        }
        IBNB(BNBAddress).deposit{ value: msg.value }();
        TransferHelper.safeTransfer(wBNBAddress, Library.pairFor(factory, path[0], path[1]), msg.value);
        if (swapFor == TypesOfTokens.NON_SUPPORTING_FEE) {
            amounts = Library.getAmountsOut(factory, msg.value, path);
            if (amounts[amounts.length - 1] < amountOutMin) {
                revert OutputAmountBelowMinimum(amounts[amounts.length - 1], amountOutMin);
            }
            _swap(amounts, path, to);
            emit SwapBnbForTokens(msg.sender, path, amounts);
        } else {
            _swapSupportingFeeOnTransferTokens(path, to);
            emit SwapBnbForTokensAtSupportingFee(msg.sender, path);
        }
    }

    function _swapExactTokensForBNB(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        TypesOfTokens swapFor
    ) internal returns (uint256[] memory amounts) {
        if (path[path.length - 1] != WBNB) {
            revert WrongAddress(BNB, path[path.length - 1]);
        }
        uint256 BNBAmount;
        if (swapFor == TypesOfTokens.NON_SUPPORTING_FEE) {
            amounts = Library.getAmountsOut(factory, amountIn, path);
            if (amounts[amounts.length - 1] < amountOutMin) {
                revert OutputAmountBelowMinimum(amounts[amounts.length - 1], amountOutMin);
            }
            TransferHelper.safeTransferFrom(
                path[0],
                msg.sender,
                Library.pairFor(factory, path[0], path[1]),
                amounts[0]
            );
            _swap(amounts, path, address(this));
            BNBAmount = amounts[amounts.length - 1];
        } else {
            uint256 balanceBefore = IBNB(BNB).balanceOf(address(this));
            TransferHelper.safeTransferFrom(
                path[0],
                msg.sender,
                Library.pairFor(factory, path[0], path[1]),
                amountIn
            );
            _swapSupportingFeeOnTransferTokens(path, address(this));
            uint256 balanceAfter = IBNB(BNB).balanceOf(address(this));
            BNBAmount = balanceAfter - balanceBefore;
        }
        IBNB(BNB).withdraw(BNBAmount);
        if (to != address(this)) {
            TransferHelper.safeTransferBNB(to, BNBAmount);
        }
        if (swapFor == TypesOfTokens.NON_SUPPORTING_FEE) {
            emit SwapTokensForBnb(msg.sender, path, amounts);
        } else {
            emit SwapTokensForBnbAtSupportingFee(msg.sender, path);
        }
    }

    function _swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) internal returns (uint256[] memory amounts) {
        amounts = Library.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert InputAmountAboveMaximum(amounts[0], amountInMax);
        }
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, to);
        emit SwapTokensForTokens(msg.sender, path, amounts);
    }

    function _swapBNBForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to
    ) internal returns (uint256[] memory amounts) {
        if (path[0] != BNB) {
            revert WrongAddress(BNB, path[0]);
        }
        amounts = Library.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > msg.value) {
            revert ExcessiveInputAmount(amounts[0], msg.value);
        }
        IBNB(BNB).deposit{ value: amounts[0] }();
        TransferHelper.safeTransfer(BNB, Library.pairFor(factory, path[0], path[1]), amounts[0]);
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferBNB(msg.sender, msg.value - amounts[0]);
        emit SwapBnbForTokens(msg.sender, path, amounts);
    }

    function _swapTokensForExactBNB(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to
    ) internal returns (uint256[] memory amounts) {
        if (path[path.length - 1] != BNB) {
            revert WrongAddress(BNB, path[path.length - 1]);
        }
        amounts = Library.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert InputAmountAboveMaximum(amounts[amounts.length - 1], amountInMax);
        }
        TransferHelper.safeTransferFrom(
            path[0],
            msg.sender,
            Library.pairFor(factory, path[0], path[1]),
            amounts[0]
        );
        _swap(amounts, path, address(this));
        IBNB(BNB).withdraw(amounts[amounts.length - 1]);
        if (to != address(this)) {
            TransferHelper.safeTransferBNB(to, amounts[amounts.length - 1]);
        }
        emit SwapTokensForBnb(msg.sender, path, amounts);
    }

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure virtual override returns (uint256 amountB) {
        return Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure virtual override returns (uint256 amountOut) {
        return Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure virtual override returns (uint256 amountIn) {
        return Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    ) external view virtual override returns (uint256[] memory amounts) {
        return Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    ) external view virtual override returns (uint256[] memory amounts) {
        return Library.getAmountsIn(factory, amountOut, path);
    }
}
