pragma solidity 0.8.13;

error SupplyError(address supplier, address Token, uint256 errorCode);

error RepayError(address repayer, address Token, uint256 errorCode);

error WrongAddress(address expectedAdddress, address passedAddress);

error SwapDeadlineExpire(uint256 deadline, uint256 timestemp);

error InsufficientInputAmount();

error InsufficientOutputAmount();

error OutputAmountBelowMinimum(uint256 amountOut, uint256 amountOutMin);

error InputAmountAboveMaximum(uint256 amountIn, uint256 amountIntMax);

error ExcessiveInputAmount(uint256 amount, uint256 amountMax);

error InsufficientLiquidity();

error ZeroAddress();

error IdenticalAddresses();

error InvalidPath();

error TokenNotListed(address Token);

error TokenUnderlyingInvalid(address underlying);

error SwapAmountLessThanAmountOutMin(uint256 swapAmount, uint256 amountOutMin);

error InsufficientBalance(uint256 sweepAmount, uint256 balance);

error SafeApproveFailed();

error SafeTransferFailed();

error SafeTransferFromFailed();

error SafeTransferBNBFailed();

error ReentrantCheck();
