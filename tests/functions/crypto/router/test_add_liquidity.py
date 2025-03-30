import pytest
import time
from eth_abi import encode
from ape import Contract


def test_add_liquidity(bob, test_token0, test_token1, router, crypto_pool_factory, alice):
    data = encode(['address', 'address'], [test_token0.address, test_token1.address]).hex()
    data = "0x" + data
    crypto_pool_factory.create_pool(data, sender=bob)


    mint_amount = int(1000000000000e18)
    test_token0.mint(bob.address, mint_amount, sender=bob)
    test_token1.mint(bob.address, mint_amount, sender=bob)
    test_token0.approve(router.address, int(2**255), sender=bob)
    test_token1.approve(router.address, int(2**255), sender=bob)

    pool = crypto_pool_factory.get_pool(test_token0.address, test_token1.address)

    p_con = Contract(pool)

    # inputs = [(test_token0.address, int(10000e18)), (test_token1.address, int(10000e18))]
    inputs = [
        {
            "token": test_token0.address,
            "amount": int(10000e18)
        },
        {
            "token": test_token1.address,
            "amount": int(10000e18)
        }
    ]
    to_data = "0x" + encode(['address'], [bob.address]).hex()
    min_liquidity = int(0)
    callback = "0x0000000000000000000000000000000000000000"
    callback_data = b""

    router.add_liquidity2(
        pool,
        inputs,
        to_data,
        min_liquidity,
        callback,
        callback_data,
        sender=bob
    )

    assert router.entered_pools_length(bob.address) == 1

    # swap
    # Constructs the swap paths with steps.
    # Determine withdraw mode, to withdraw native ETH or wETH on last step.
    # 0 - vault internal transfer
    # 1 - withdraw and unwrap to naitve ETH
    # 2 - withdraw and wrap to wETH
    mode = 1
    swap_data = "0x" + encode(['address', 'address', 'uint8'], [test_token0.address, bob.address, mode]).hex()
    # steps = [{
    #     "pool": pool,
    #     "data": swap_data,
    #     "callback": callback,
    #     "callback_data": "0x"
    # }]
    # paths = [{
    #     "steps": steps,
    #     "token_in": test_token0.address,
    #     "amount_in": int(100e18)
    # }]
    steps = [(
        pool,
        swap_data,
        callback,
        callback_data
    )]
    paths = [(
        steps,
        test_token0.address,
        int(100e18)
    )]

    amount_out_min = 0
    deadline = int(time.time()) + 1800

    router.swap(paths, amount_out_min, deadline, sender=bob)
