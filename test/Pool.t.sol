// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Pool} from "../src/libraries/Pool.sol";
import {PoolManager} from "../src/PoolManager.sol";
import {Position} from "../src/libraries/Position.sol";
import {TickMath} from "../src/libraries/TickMath.sol";
import {TickBitmap} from "../src/libraries/TickBitmap.sol";
import {LiquidityAmounts} from "./utils/LiquidityAmounts.sol";
import {SafeCast} from "../src/libraries/SafeCast.sol";

contract PoolTest is Test {
    using Pool for Pool.State;

    Pool.State state;

    function testPoolInitialize(uint160 sqrtPriceX96, uint16 protocolFee, uint16 hookFee, uint24 dynamicFee) public {
        vm.assume(protocolFee < 2 ** 12 && hookFee < 2 ** 12);

        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 >= TickMath.MAX_SQRT_RATIO) {
            vm.expectRevert(TickMath.InvalidSqrtRatio.selector);
            state.initialize(
                sqrtPriceX96,
                _formatSwapAndWithdrawFee(protocolFee, protocolFee),
                _formatSwapAndWithdrawFee(hookFee, hookFee),
                dynamicFee
            );
        } else {
            state.initialize(
                sqrtPriceX96,
                _formatSwapAndWithdrawFee(protocolFee, protocolFee),
                _formatSwapAndWithdrawFee(hookFee, hookFee),
                dynamicFee
            );
            assertEq(state.slot0.sqrtPriceX96, sqrtPriceX96);
            assertEq(state.slot0.protocolFees >> 12, protocolFee);
            assertEq(state.slot0.tick, TickMath.getTickAtSqrtRatio(sqrtPriceX96));
            assertLt(state.slot0.tick, TickMath.MAX_TICK);
            assertGt(state.slot0.tick, TickMath.MIN_TICK - 1);
        }
    }

    function testModifyPosition(uint160 sqrtPriceX96, Pool.ModifyPositionParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing >= TickMath.MIN_TICK_SPACING);
        vm.assume(params.tickSpacing <= TickMath.MAX_TICK_SPACING);

        testPoolInitialize(sqrtPriceX96, 0, 0, 0);

        if (params.tickLower >= params.tickUpper) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TicksMisordered.selector, params.tickLower, params.tickUpper));
        } else if (params.tickLower < TickMath.MIN_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLowerOutOfBounds.selector, params.tickLower));
        } else if (params.tickUpper > TickMath.MAX_TICK) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickUpperOutOfBounds.selector, params.tickUpper));
        } else if (params.liquidityDelta < 0) {
            vm.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        } else if (params.liquidityDelta == 0) {
            vm.expectRevert(Position.CannotUpdateEmptyPosition.selector);
        } else if (params.liquidityDelta > int128(Pool.tickSpacingToMaxLiquidityPerTick(params.tickSpacing))) {
            vm.expectRevert(abi.encodeWithSelector(Pool.TickLiquidityOverflow.selector, params.tickLower));
        } else if (params.tickLower % params.tickSpacing != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickLower, params.tickSpacing)
            );
        } else if (params.tickUpper % params.tickSpacing != 0) {
            vm.expectRevert(
                abi.encodeWithSelector(TickBitmap.TickMisaligned.selector, params.tickUpper, params.tickSpacing)
            );
        } else {
            // We need the assumptions above to calculate this
            uint256 maxInt128 = uint256(uint128(type(int128).max));
            (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
                sqrtPriceX96,
                TickMath.getSqrtRatioAtTick(params.tickLower),
                TickMath.getSqrtRatioAtTick(params.tickUpper),
                uint128(params.liquidityDelta)
            );

            if ((amount0 > maxInt128) || (amount1 > maxInt128)) {
                vm.expectRevert(abi.encodeWithSelector(SafeCast.SafeCastOverflow.selector));
            }
        }

        params.owner = address(this);
        state.modifyPosition(params);
    }

    function testSwap(uint160 sqrtPriceX96, uint24 swapFee, Pool.SwapParams memory params) public {
        // Assumptions tested in PoolManager.t.sol
        vm.assume(params.tickSpacing >= TickMath.MIN_TICK_SPACING);
        vm.assume(params.tickSpacing <= TickMath.MAX_TICK_SPACING);
        vm.assume(swapFee < 1000000);

        testPoolInitialize(sqrtPriceX96, 0, 0, 0);
        Pool.Slot0 memory slot0 = state.slot0;

        if (params.amountSpecified == 0) {
            vm.expectRevert(Pool.SwapAmountCannotBeZero.selector);
        } else if (params.zeroForOne) {
            if (params.sqrtPriceLimitX96 >= slot0.sqrtPriceX96) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 <= TickMath.MIN_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        } else if (!params.zeroForOne) {
            if (params.sqrtPriceLimitX96 <= slot0.sqrtPriceX96) {
                vm.expectRevert(
                    abi.encodeWithSelector(
                        Pool.PriceLimitAlreadyExceeded.selector, slot0.sqrtPriceX96, params.sqrtPriceLimitX96
                    )
                );
            } else if (params.sqrtPriceLimitX96 >= TickMath.MAX_SQRT_RATIO) {
                vm.expectRevert(abi.encodeWithSelector(Pool.PriceLimitOutOfBounds.selector, params.sqrtPriceLimitX96));
            }
        }

        state.swap(params);

        if (params.zeroForOne) {
            assertLe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        } else {
            assertGe(state.slot0.sqrtPriceX96, params.sqrtPriceLimitX96);
        }
    }

    function _formatSwapAndWithdrawFee(uint16 swapFee, uint16 withdrawFee) internal pure returns (uint24) {
        return (uint24(swapFee) << 12) | withdrawFee;
    }
}
