import pytest
from eth_abi import encode 

def test_create_pool(bob, crypto_pool_factory, test_token0, test_token1, pool_master):
    data = encode(['address', 'address'], [test_token0.address, test_token1.address]).hex()
    data = "0x" + data
    crypto_pool_factory.create_pool(data, sender=bob)

    assert pool_master.is_pool(crypto_pool_factory.get_pool(test_token0.address, test_token1.address)) == True